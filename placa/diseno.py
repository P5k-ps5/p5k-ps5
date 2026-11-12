"""Placa propia del puente: ESP32-S3 + MAX3421E en una sola PCB, con dos USB-C.

Este archivo es la única fuente de verdad: qué componentes hay y qué patilla va a qué red. De aquí salen el
esquema (esquema.py) y la placa (pcb.py), así que no pueden no cuadrar entre sí.

Pines del ESP32-S3 iguales que en el montaje actual (main/max3421_glue.c, main/main.c): el firmware vale tal cual.
- USB nativo (IO19/IO20) -> USB-C «CONSOLA» (PS5, P5Mate o el Mac)
- MAX3421E por SPI: SCK IO12, MOSI IO11, MISO IO13, SS IO10, INT IO9, RES IO8
- USB-C «MANDO» (host del MAX3421E), con su VBUS a través de un interruptor (IO5 a nivel bajo lo apaga; por
  defecto encendido, así no hace falta tocar el firmware)
- LED RGB WS2812B en IO48, BOOT en IO0
- Pantalla: I2C (SDA IO6, SCL IO7) y SPI aparte (SCK IO15, MOSI IO16, MISO IO17, CS IO18, DC IO21, RST IO38,
  BL IO14, táctil CS IO40, táctil INT IO41)
"""

# Piezas de JLCPCB/LCSC comprobadas en jlcpcb.com/partdetail (nov 2026)
LCSC = {
    "R10k": "C25744", "R5k1": "C25905", "R56k": "C25796", "R33": "C25105", "R100k": "C25741",
    "C100n": "C1525", "C1u": "C52923", "C10u": "C19702", "C22u": "C45783", "C20p": "C1554",
}

FP_R = "Resistor_SMD:R_0402_1005Metric"
FP_C = "Capacitor_SMD:C_0402_1005Metric"


def R(ref, valor, a, b, lcsc):
    return dict(ref=ref, sym="Device:R", valor=valor, fp=FP_R, lcsc=lcsc, pines={"1": a, "2": b})


def C(ref, valor, a, b, lcsc, fp=FP_C):
    return dict(ref=ref, sym="Device:C", valor=valor, fp=fp, lcsc=lcsc, pines={"1": a, "2": b})


def usb_c(ref, valor, vbus, cc1, cc2, dp, dm):
    return dict(ref=ref, sym="Connector:USB_C_Receptacle_USB2.0_16P", valor=valor,
                fp="Connector_USB:USB_C_Receptacle_HRO_TYPE-C-31-M-12", lcsc="C165948",
                pines={"A1": "GND", "A12": "GND", "B1": "GND", "B12": "GND",
                       "A4": vbus, "A9": vbus, "B4": vbus, "B9": vbus,
                       "A5": cc1, "B5": cc2, "A6": dp, "B6": dp, "A7": dm, "B7": dm, "SH": "GND"})


# Patillas del ESP32-S3-WROOM-1 (número de la huella = número del símbolo)
ESP32 = {
    "1": "GND", "2": "+3V3", "3": "EN",
    "5": "MANDO_EN",      # IO5: interruptor del VBUS del mando
    "6": "SDA", "7": "SCL",  # IO6, IO7
    "8": "LCD_SCK", "9": "LCD_MOSI", "10": "LCD_MISO", "11": "LCD_CS",  # IO15..IO18
    "12": "MAX_RES",      # IO8
    "13": "USB_DM", "14": "USB_DP",  # IO19, IO20
    "17": "MAX_INT", "18": "MAX_SS", "19": "MAX_MOSI", "20": "MAX_SCK", "21": "MAX_MISO",  # IO9..IO13
    "23": "LCD_DC",       # IO21
    "25": "LED_DIN",      # IO48
    "27": "BOOT",         # IO0
    "22": "LCD_BL",       # IO14 (en la fila de abajo, al lado del conector de pantalla)
    "31": "LCD_RST", "33": "T_CS", "34": "T_INT",  # IO38, IO40, IO41
    "36": "RXD0", "37": "TXD0",
    "40": "GND", "41": "GND",
}

# MAX3421E en TQFN-32 de 5x5 mm (MAX3421EETJ+T): el TQFP (EEHJ+T) está agotado en JLCPCB. Mismo patillaje en los
# dos encapsulados (hoja de datos de Maxim, Pin Configurations, 19-3953); el TQFN añade la almohadilla de debajo
# (EP, patilla 33 en la huella de KiCad), que va a masa.
MAX3421E_PINES = {
    1: "GPIN7", 2: "VL", 3: "GND", 4: "GPOUT0", 5: "GPOUT1", 6: "GPOUT2", 7: "GPOUT3", 8: "GPOUT4",
    9: "GPOUT5", 10: "GPOUT6", 11: "GPOUT7", 12: "~{RES}", 13: "SCLK", 14: "~{SS}", 15: "MISO", 16: "MOSI",
    17: "GPX", 18: "INT", 19: "GND", 20: "D-", 21: "D+", 22: "VBCOMP", 23: "VCC", 24: "XI",
    25: "XO", 26: "GPIN0", 27: "GPIN1", 28: "GPIN2", 29: "GPIN3", 30: "GPIN4", 31: "GPIN5", 32: "GPIN6",
    33: "EP",
}
MAX3421E = {"2": "+3V3", "3": "GND", "12": "MAX_RES", "13": "MAX_SCK", "14": "MAX_SS", "15": "MAX_MISO",
            "16": "MAX_MOSI", "18": "MAX_INT", "19": "GND", "20": "MAX_DM", "21": "MAX_DP",
            "22": "VBUS_MANDO", "23": "+3V3", "24": "XI", "25": "XO", "33": "GND"}

COMPONENTES = [
    # --- ESP32-S3 ---
    dict(ref="U1", sym="RF_Module:ESP32-S3-WROOM-1", valor="ESP32-S3-WROOM-1-N16R8",
         fp="RF_Module:ESP32-S3-WROOM-1", lcsc="C2913202", pines=ESP32),
    R("R1", "10k", "+3V3", "EN", LCSC["R10k"]),
    C("C4", "1u", "EN", "GND", LCSC["C1u"]),
    dict(ref="SW2", sym="Switch:SW_Push", valor="RST", fp="Button_Switch_SMD:SW_Push_1P1T_XKB_TS-1187A",
         lcsc="C318884", pines={"1": "EN", "2": "GND"}),
    R("R2", "10k", "+3V3", "BOOT", LCSC["R10k"]),
    dict(ref="SW1", sym="Switch:SW_Push", valor="BOOT", fp="Button_Switch_SMD:SW_Push_1P1T_XKB_TS-1187A",
         lcsc="C318884", pines={"1": "BOOT", "2": "GND"}),
    C("C3", "100n", "+3V3", "GND", LCSC["C100n"]),
    C("C14", "10u", "+3V3", "GND", LCSC["C10u"], "Capacitor_SMD:C_0603_1608Metric"),

    # --- USB-C de la consola y alimentación ---
    usb_c("J1", "CONSOLA", "VBUS", "CC1_CONSOLA", "CC2_CONSOLA", "USB_DP", "USB_DM"),
    R("R13", "5.1k", "CC1_CONSOLA", "GND", LCSC["R5k1"]),
    R("R14", "5.1k", "CC2_CONSOLA", "GND", LCSC["R5k1"]),
    dict(ref="U4", sym="Power_Protection:USBLC6-2SC6", valor="USBLC6-2SC6", fp="Package_TO_SOT_SMD:SOT-23-6",
         lcsc="C7519", pines={"1": "USB_DP", "6": "USB_DP", "3": "USB_DM", "4": "USB_DM", "2": "GND", "5": "VBUS"}),
    dict(ref="U3", sym="Regulator_Linear:AMS1117-3.3", valor="AMS1117-3.3", fp="Package_TO_SOT_SMD:SOT-223-3_TabPin2",
         lcsc="C6186", pines={"1": "GND", "2": "+3V3", "3": "VBUS"}),
    C("C1", "22u", "VBUS", "GND", LCSC["C22u"], "Capacitor_SMD:C_0805_2012Metric"),
    # Más reserva en VBUS: al enchufar el mando en caliente, sus condensadores tiran de aquí de golpe
    C("C15", "22u", "VBUS", "GND", LCSC["C22u"], "Capacitor_SMD:C_0805_2012Metric"),
    C("C2", "22u", "+3V3", "GND", LCSC["C22u"], "Capacitor_SMD:C_0805_2012Metric"),

    # --- LED RGB (a 5 V menos un diodo: así entiende los 3,3 V del ESP32) ---
    dict(ref="D2", sym="Diode:1N4148W", valor="1N4148W", fp="Diode_SMD:D_SOD-123", lcsc="C81598",
         pines={"1": "LED_VDD", "2": "VBUS"}),
    dict(ref="D1", sym="LED:WS2812B-2020", valor="WS2812B-2020-V6", fp="LED_SMD:LED_WS2812B-2020_PLCC4_2.0x2.0mm",
         lcsc="C52917434", pines={"2": "GND", "3": "LED_DIN", "4": "LED_VDD"}),
    C("C5", "100n", "LED_VDD", "GND", LCSC["C100n"]),

    # --- MAX3421E ---
    dict(ref="U2", sym="puente:MAX3421E", valor="MAX3421EETJ+T", fp="Package_DFN_QFN:TQFN-32-1EP_5x5mm_P0.5mm_EP3.1x3.1mm",
         lcsc="C1870151", pines=MAX3421E),
    C("C6", "1u", "+3V3", "GND", LCSC["C1u"]),
    C("C7", "100n", "+3V3", "GND", LCSC["C100n"]),
    C("C8", "100n", "+3V3", "GND", LCSC["C100n"]),
    C("C9", "1u", "VBUS_MANDO", "GND", LCSC["C1u"]),
    R("R3", "10k", "+3V3", "MAX_RES", LCSC["R10k"]),
    R("R4", "10k", "+3V3", "MAX_INT", LCSC["R10k"]),
    R("R15", "10k", "+3V3", "MAX_SS", LCSC["R10k"]),   # SS en reposo mientras arranca el ESP32
    dict(ref="Y1", sym="Device:Crystal_GND24", valor="12MHz", fp="Crystal:Crystal_SMD_3225-4Pin_3.2x2.5mm",
         lcsc="C9002", pines={"1": "XI", "3": "XO", "2": "GND", "4": "GND"}),
    C("C10", "20p", "XI", "GND", LCSC["C20p"]),
    C("C11", "20p", "XO", "GND", LCSC["C20p"]),
    R("R5", "33", "MAX_DP", "MANDO_DP", LCSC["R33"]),
    R("R6", "33", "MAX_DM", "MANDO_DM", LCSC["R33"]),

    # --- USB-C del mando (el puerto da corriente: 56k en los CC hacia VBUS) ---
    usb_c("J2", "MANDO", "VBUS_MANDO", "CC1_MANDO", "CC2_MANDO", "MANDO_DP", "MANDO_DM"),
    R("R7", "56k", "CC1_MANDO", "VBUS_MANDO", LCSC["R56k"]),
    R("R8", "56k", "CC2_MANDO", "VBUS_MANDO", LCSC["R56k"]),
    C("C12", "22u", "VBUS_MANDO", "GND", LCSC["C22u"], "Capacitor_SMD:C_0805_2012Metric"),

    # --- Interruptor del VBUS del mando, con arranque suave (evita el bajón al enchufar el mando en caliente) ---
    dict(ref="Q1", sym="Transistor_FET:AO3401A", valor="AO3401A", fp="Package_TO_SOT_SMD:SOT-23",
         lcsc="C15127", pines={"1": "Q1_G", "2": "VBUS", "3": "VBUS_MANDO"}),
    R("R9", "100k", "Q1_G", "VBUS", LCSC["R100k"]),
    C("C13", "100n", "Q1_G", "VBUS", LCSC["C100n"]),
    R("R10", "10k", "Q1_G", "Q2_D", LCSC["R10k"]),
    dict(ref="Q2", sym="Transistor_FET:2N7002", valor="2N7002", fp="Package_TO_SOT_SMD:SOT-23",
         lcsc="C8545", pines={"1": "MANDO_ON", "2": "GND", "3": "Q2_D"}),
    R("R11", "100k", "MANDO_ON", "+3V3", LCSC["R100k"]),
    R("R12", "10k", "MANDO_EN", "MANDO_ON", LCSC["R10k"]),

    # --- Conectores para pantalla (sin montar: se sueldan solo si se usa) ---
    dict(ref="J3", sym="Connector_Generic:Conn_01x04", valor="OLED I2C", dnp=True,
         fp="Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical", lcsc="",
         pines={"1": "GND", "2": "+3V3", "3": "SCL", "4": "SDA"}),
    dict(ref="J4", sym="Connector_Generic:Conn_02x07_Odd_Even", valor="PANTALLA SPI", dnp=True,
         fp="Connector_PinHeader_2.54mm:PinHeader_2x07_P2.54mm_Vertical", lcsc="",
         pines={"1": "+3V3", "2": "GND", "3": "LCD_SCK", "4": "LCD_MOSI", "5": "LCD_MISO", "6": "LCD_CS",
                "7": "LCD_DC", "8": "LCD_RST", "9": "LCD_BL", "10": "T_CS", "11": "T_INT", "12": "SDA",
                "13": "SCL", "14": "VBUS"}),

    # --- Puntos de prueba (rescate por UART y medidas) ---
    *[dict(ref=f"TP{i}", sym="Connector:TestPoint", valor=n, fp="TestPoint:TestPoint_Pad_D1.0mm", lcsc="",
           dnp=True, pines={"1": n})
      for i, n in enumerate(["TXD0", "RXD0", "GND", "+3V3", "BOOT", "EN"], 1)],
]

# Redes que necesitan PWR_FLAG para el ERC (las alimenta algo pasivo: el USB, un MOSFET o un diodo)
BANDERAS = ["GND", "VBUS", "VBUS_MANDO", "LED_VDD"]
