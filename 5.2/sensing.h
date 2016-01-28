#ifndef SENSING_H_
#define SENSING_H_

#include <IPDispatch.h>

enum {
  SETTINGS_REQUEST = 1,
  SETTINGS_RESPONSE = 2,
  SETTINGS_USER = 4
};


typedef nx_struct settings {
  nx_uint16_t threshold;
  nx_uint32_t sample_time;
  nx_uint32_t sample_period;
} settings_t;

nx_struct settings_report {
  nx_uint16_t sender;
  nx_uint8_t type;
  settings_t settings;
};

nx_struct alarm_report {
  nx_uint16_t source;
};

nx_struct alarm_state {
  nx_uint16_t state;
  nx_uint16_t variance;
};

#define REPORT_DEST "fec0::100"
#define MULTICAST "ff02::1"

#endif
