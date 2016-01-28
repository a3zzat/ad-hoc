#include <lib6lowpan/ip.h>
#include "sensing.h"
#include "blip_printf.h"

module SensingP {
	uses {
		interface Boot;
		interface Leds;
		interface SplitControl as RadioControl;

		interface UDP as Alarm;
		interface UDP as Settings;

		interface ShellCommand as GetCmd;
		interface ShellCommand as SetCmd;

		interface Timer<TMilli> as Sample_timer;

		interface ReadStream<uint16_t> as StreamPar;

		interface Mount as ConfigMount;
		interface ConfigStorage;
	}
} implementation {

	enum {
		DEFAULT_PERIOD = 256, // ms
		DEFAULT_SAMPLE_TIME = 10000, // ms
		DEFAULT_THRESHOLD = 100,
		SAMPLE_SIZE = 20
	};

	uint16_t m_parSamples[SAMPLE_SIZE];
	uint8_t settings_source;
	nx_struct settings_report report;
	nx_struct alarm_report alarm;
	nx_struct alarm_state alarm_local;
	settings_t settings_local;
	struct sockaddr_in6 multicast_4;
	struct sockaddr_in6 multicast_7;

	task void SendSettings();
  task void UpdateSettings();

	event void Boot.booted() {
		multicast_7.sin6_port = htons(7000);
		inet_pton6(MULTICAST, &multicast_7.sin6_addr);
		call Alarm.bind(7000);

		multicast_4.sin6_port = htons(4000);
		inet_pton6(MULTICAST, &multicast_4.sin6_addr);
		call Settings.bind(4000);
		settings_source = 0;
		report.sender =TOS_NODE_ID;
		alarm.source = TOS_NODE_ID;
		alarm_local.state = 0;
		alarm_local.variance = 0;
		call Leds.led0Off();
		call Leds.led1Off();
		call Leds.led2Off();
		call ConfigMount.mount();
	}

	//radio
	event void RadioControl.startDone(error_t e) {
	report.type = SETTINGS_REQUEST;
	call Sample_timer.startOneShot(10000);
	post SendSettings();
	}

	event void RadioControl.stopDone(error_t e) {}



	//config

	event void ConfigMount.mountDone(error_t e){
		call RadioControl.start();
	}

	event void ConfigStorage.readDone(storage_addr_t addr, void* buf, storage_len_t len, error_t e) {
	}

	event void ConfigStorage.writeDone(storage_addr_t addr, void* buf, storage_len_t len, error_t e) {
		call ConfigStorage.commit();
	}

	event void ConfigStorage.commitDone(error_t error) {}


//timer
event void Sample_timer.fired() {
	if (settings_source == 0){

/*
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
PROBLEM!
OLD data still in eeprom, has  to be updated at least once to every mote either through direct shell or over the multicast network
Left it in since it is nicer
*/
		if (call ConfigStorage.valid()) {
			call ConfigStorage.read(0, &settings_local, sizeof(settings_local));
			settings_source = 2;
			call Leds.led1On();
		}

		// END OF PROBLEM

		else {
			settings_local.sample_period = DEFAULT_PERIOD;
			settings_local.threshold = DEFAULT_THRESHOLD;
			settings_local.sample_time = DEFAULT_SAMPLE_TIME;
			settings_source = 3;
			call Leds.led2On();
		}
		call Sample_timer.startPeriodic(settings_local.sample_time);
	} else if(alarm_local.state == 1){
		call Leds.led0Toggle();
		call Leds.led1Toggle();
		call Leds.led2Toggle();
	} else {
	call StreamPar.postBuffer(m_parSamples, SAMPLE_SIZE);
	call StreamPar.read(settings_local.sample_period);
	}
}

	//udp interfaces

	event void Alarm.recvfrom(struct sockaddr_in6 *from, void *data, uint16_t len, struct ip6_metadata *meta) {
		memcpy(&alarm, data, sizeof(alarm));

		//Interface to diplay more numbers needed!
		//
		//
		//

		if(alarm.source & 0x0001){
			call Leds.led0On();
		} else{
			call Leds.led0Off();
		}
		if(alarm.source & 0x0002){
			call Leds.led1On();
		} else{
			call Leds.led1Off();
		}

		if(alarm.source & 0x0004){
			call Leds.led2On();
		} else{
			call Leds.led2Off();
		}
	}

	event void Settings.recvfrom(struct sockaddr_in6 *from, void *data, uint16_t len, struct ip6_metadata *meta) {
		nx_struct settings_report recv_report;
		memcpy(&recv_report, data, sizeof(recv_report));

		switch(recv_report.type){
			case SETTINGS_REQUEST:
			report.type = SETTINGS_RESPONSE;
			memcpy(&report.settings, &settings_local, sizeof(settings_local));
		  post SendSettings();
			break;

			case SETTINGS_RESPONSE:
			if(settings_source == 0){
			memcpy(&settings_local, &recv_report.settings, sizeof(settings_local));
			settings_source = 1;
			call Sample_timer.stop();
			call Sample_timer.startPeriodic(settings_local.sample_time);
			post UpdateSettings();
			}
			break;

			case SETTINGS_USER:
			memcpy(&settings_local, &recv_report.settings, sizeof(settings_local));
			settings_source = 1;
			call Sample_timer.stop();
			call Sample_timer.startPeriodic(settings_local.sample_time);
			post UpdateSettings();
			break;
		}
	}

	task void SendSettings() {
		call Settings.sendto(&multicast_4, &report, sizeof(report));
	}

	task void UpdateSettings() {
	 call ConfigStorage.write(0, &settings_local, sizeof(settings_local));
	}

	task void SendAlarm() {
		call Alarm.sendto(&multicast_7, &alarm, sizeof(alarm));
	}

	//process data
	task void checkSmoke(){
	uint8_t i;
	uint32_t total = 0;
	uint16_t average;
	uint16_t variance;

//calc average
		for (i = 0; i < SAMPLE_SIZE; i++) {
			total = total + m_parSamples[i];
		}

		average = total/SAMPLE_SIZE;
		total = 0;
//calc variance
		for (i = 0; i < SAMPLE_SIZE; i++) {
		            total += (average-m_parSamples[i])*(average-m_parSamples[i]); //unsure about this exact implementation
			}

			variance = total/SAMPLE_SIZE;
			alarm_local.variance = variance;

		if (variance >  settings_local.threshold){
			call Leds.led0Off();
			call Leds.led1Off();
			call Leds.led2Off();
			alarm_local.state = 1;
			call Sample_timer.stop();
			call Sample_timer.startPeriodic(500);
			post SendAlarm();
		}
	}

	//udp shell

	event char *GetCmd.eval(int argc, char **argv) {
		char *ret = call GetCmd.getBuffer(64);
		if (ret != NULL) {
call Leds.led2On();

		sprintf(ret, "Thr: %d\nPer: %d\nSTime: %d\n state: %d\n var: %d\n Src: %d", settings_local.threshold, settings_local.sample_period, settings_local.sample_time,alarm_local.state,alarm_local.variance,settings_source);

		}
		return ret;
	}

	event char *SetCmd.eval(int argc, char **argv) {
		char *ret = call SetCmd.getBuffer(40);
		if (ret != NULL) {
			if (argc == 3) {
				if (!strcmp("per",argv[1])) {
					settings_local.sample_period = atoi(argv[2]);
					sprintf(ret, ">>>Period changed to %u\n",settings_local.sample_period);
					report.type = SETTINGS_USER;
					post SendSettings();
				} else if (!strcmp("th", argv[1])) {
					settings_local.threshold = atoi(argv[2]);
					sprintf(ret, ">>>Threshold changed to %u\n",settings_local.threshold);
					report.type = SETTINGS_USER;
					post SendSettings();
				} else if (!strcmp("st", argv[1])) {
			  	settings_local.sample_time = atoi(argv[2]);
					sprintf(ret, ">>>Sample Time changed to %u\n",settings_local.sample_time);
					report.type = SETTINGS_USER;
					post SendSettings();
				}
				else {
					strcpy(ret,"Usage: set per|th|st [<sampleperiod in ms>|<threshold>|<sampletime in ms>]\n");
				}
			} else {
			strcpy(ret,"Usage: set per|th|st [<sampleperiod in ms>|<threshold>|<sampletime in ms>]\n");
				}
			}
			else {
			strcpy(ret,"Usage: set per|th|st [<sampleperiod in ms>|<threshold>|<sampletime in ms>]\n");
			}
		return ret;
		}

		event void StreamPar.readDone(error_t ok, uint32_t usActualPeriod) {
				return;
		}

		event void StreamPar.bufferDone(error_t ok, uint16_t *buf,uint16_t count) {
			if (ok == SUCCESS) {
			post checkSmoke();
			}
		}
}
