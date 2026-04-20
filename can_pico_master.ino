#include <Arduino.h>
#include "hardware/pio.h"
#include "hardware/irq.h"
#include "hardware/clocks.h"

extern "C" {
  #include "can2040.h" 
  }

static struct can2040 g_can;

static volatile uint32_t rx_count = 0;
static volatile uint32_t bad_count = 0;

static void can_cb(struct can2040 *cd, uint32_t notify, struct can2040_msg *msg) {
  (void)cd;
  if (notify != CAN2040_NOTIFY_RX) return;

  if (msg->id == 0x124 && msg->dlc >= 2) rx_count++;
  else bad_count++;
}

void pio1_irq0_handler() { can2040_pio_irq_handler(&g_can); }

static void can_send_u16(uint32_t id, uint16_t v) {
  struct can2040_msg tx = {};
  tx.id = id;
  tx.dlc = 2;
  tx.data[0] = (uint8_t)(v & 0xFF);
  tx.data[1] = (uint8_t)(v >> 8);
  can2040_transmit(&g_can, &tx);
}

static uint32_t tx_count = 0;

void setup() {
  Serial.begin(115200);
  delay(1500);

  can2040_setup(&g_can, 1);
  can2040_callback_config(&g_can, can_cb);

  uint32_t sys_hz = clock_get_hz(clk_sys);
  can2040_start(&g_can, sys_hz, 125000, 20, 21);

  irq_set_exclusive_handler(PIO1_IRQ_0, pio1_irq0_handler);
  irq_set_enabled(PIO1_IRQ_0, true);
}

void loop() {
  static uint32_t t_send = 0;
  static uint16_t counter = 0;

  if (millis() - t_send >= 100) {      // 1ms stress
    can_send_u16(0x123, counter++);//counter++
    tx_count++;
    t_send = millis();
  }

  static uint32_t t_print = 0;
  if (millis() - t_print >= 1000) {
    noInterrupts();
    uint32_t rx = rx_count, bad = bad_count;
    interrupts();

    Serial.print("TX=");
    Serial.print(tx_count);
    Serial.print(" RX=");
    Serial.print(rx);
    Serial.print(" bad=");
    Serial.println(bad);

    t_print = millis();
  }
}
