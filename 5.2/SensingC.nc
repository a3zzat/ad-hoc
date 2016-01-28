#include "StorageVolumes.h"

configuration SensingC {

} implementation {
	components MainC, LedsC, SensingP;
	SensingP.Boot -> MainC;
	SensingP.Leds -> LedsC;

	components IPStackC;
	components RPLRoutingC;
	components StaticIPAddressTosIdC;
	SensingP.RadioControl -> IPStackC;

	components UdpC;
	components new UdpSocketC() as Alarm;
	SensingP.Alarm -> Alarm;
	components new UdpSocketC() as Settings;
	SensingP.Settings -> Settings;

	components UDPShellC;
	components new ShellCommandC("get") as GetCmd;
	components new ShellCommandC("set") as SetCmd;
	SensingP.GetCmd -> GetCmd;
	SensingP.SetCmd -> SetCmd;


	components new TimerMilliC() as Sample_timer;
	SensingP.Sample_timer -> Sample_timer;

	components new HamamatsuS1087ParC() as SensorPar;
	SensingP.StreamPar -> SensorPar.ReadStream;

	components new ConfigStorageC(VOLUME_CONFIG) as Configsettings;
	SensingP.ConfigMount -> Configsettings;
	SensingP.ConfigStorage -> Configsettings;
}
