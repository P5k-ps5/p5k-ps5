idf_component_register(SRCS "main.c" "mando.c" "ordenes.c" "usb_ps4.c" "max3421_glue.c" "host_mando.c"
                            "red.c" "web.c" "sincro.c"
                       INCLUDE_DIRS ".")

# La app web: la misma página que sirven la app de Mac y la de escritorio (app/Pagina.swift), comprimida
# con gzip al compilar, y el icono de la app de escritorio.
idf_build_get_property(python PYTHON)
set(PAGINA_SWIFT ${CMAKE_CURRENT_LIST_DIR}/../app/Pagina.swift)
set(PAGINA_GZ ${CMAKE_CURRENT_BINARY_DIR}/pagina.html.gz)
add_custom_command(
    OUTPUT ${PAGINA_GZ}
    COMMAND ${python} ${CMAKE_CURRENT_LIST_DIR}/../herramientas/pagina.py ${PAGINA_SWIFT} ${PAGINA_GZ}
    DEPENDS ${PAGINA_SWIFT} ${CMAKE_CURRENT_LIST_DIR}/../herramientas/pagina.py
    COMMENT "Sacando la página web de app/Pagina.swift")
add_custom_target(pagina_web DEPENDS ${PAGINA_GZ})
add_dependencies(${COMPONENT_LIB} pagina_web)
target_add_binary_data(${COMPONENT_LIB} ${PAGINA_GZ} BINARY)
target_add_binary_data(${COMPONENT_LIB} ${CMAKE_CURRENT_LIST_DIR}/../escritorio/src-tauri/icons/128x128@2x.png BINARY)

# Hito 2 (passthrough con el mando real por MAX3421E):
# El componente tinyusb solo compila los fuentes de DEVICE. Añadimos aquí los de HOST y activamos el
# host con CFG_TUH_*, sin tocar el componente gestionado (que está gitignoreado). Device por el OTG
# nativo (PS5) y host por el MAX3421E (SPI) conviven en el ESP32-S3.
idf_component_get_property(tusb_lib espressif__tinyusb COMPONENT_LIB)
idf_component_get_property(tusb_dir espressif__tinyusb COMPONENT_DIR)
target_sources(${tusb_lib} PRIVATE
    "${tusb_dir}/src/host/usbh.c"
    "${tusb_dir}/src/host/hub.c"
    "${tusb_dir}/src/portable/analog/max3421/hcd_max3421.c"
    "${tusb_dir}/src/class/hid/hid_host.c")

set(tuh_defs
    CFG_TUH_ENABLED=1
    CFG_TUH_MAX3421=1
    CFG_TUH_HUB=0
    CFG_TUH_DEVICE_MAX=1
    CFG_TUH_HID=4
    CFG_TUH_ENUMERATION_BUFSIZE=512)
target_compile_definitions(${tusb_lib} PRIVATE ${tuh_defs})
target_compile_definitions(${COMPONENT_LIB} PRIVATE ${tuh_defs})

# Las 3 funciones de glue del MAX3421E viven en main (max3421_glue.c) pero las referencia la lib de
# tinyusb (hcd_max3421.c) -> dependencia inversa. Le decimos a la lib de tinyusb que depende de main;
# el ciclo main<->tinyusb lo resuelve ESP-IDF con grupos de link (--start-group/--end-group).
target_link_libraries(${tusb_lib} PRIVATE ${COMPONENT_LIB})
