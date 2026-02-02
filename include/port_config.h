#ifndef PORT_CONFIG_H
#define PORT_CONFIG_H

typedef struct {
    unsigned char addr_port;
    unsigned char data_port;
} port_config_t;

// External declarations - implemented in ym2149.c
extern port_config_t ym2149_ports;

void port_config_init(void);
void port_config_set(unsigned char addr_port, unsigned char data_port);
int port_config_load_from_file(const char* filename);
int port_config_validate(void);

#endif