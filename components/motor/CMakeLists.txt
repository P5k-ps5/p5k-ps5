# El motor en Rust (components/motor): se compila con cargo (toolchain "esp" de espup) como biblioteca
# estática y se enlaza con el firmware. Comparte los .rs del motor con la app de escritorio.
idf_component_register(SRCS "compat.c" INCLUDE_DIRS "include")

set(MOTOR_DIR ${CMAKE_CURRENT_LIST_DIR})
set(MOTOR_LIB ${MOTOR_DIR}/target/xtensa-esp32s3-espidf/release/libmotor.a)
find_program(CARGO cargo HINTS $ENV{HOME}/.cargo/bin REQUIRED)
file(GLOB MOTOR_FUENTES ${MOTOR_DIR}/src/*.rs ${MOTOR_DIR}/../../escritorio/src-tauri/src/*.rs)

add_custom_command(
    OUTPUT ${MOTOR_LIB}
    COMMAND ${CMAKE_COMMAND} -E env --unset=CC --unset=CXX --unset=CFLAGS --unset=CXXFLAGS --unset=AR
            ${CARGO} build --release
    WORKING_DIRECTORY ${MOTOR_DIR}
    DEPENDS ${MOTOR_FUENTES} ${MOTOR_DIR}/Cargo.toml
    COMMENT "Compilando el motor en Rust (cargo)"
    USES_TERMINAL)
add_custom_target(motor_cargo DEPENDS ${MOTOR_LIB})

add_library(motor_rust STATIC IMPORTED GLOBAL)
set_target_properties(motor_rust PROPERTIES IMPORTED_LOCATION ${MOTOR_LIB})
add_dependencies(motor_rust motor_cargo)
target_link_libraries(${COMPONENT_LIB} PUBLIC motor_rust)
# realpath está en compat.c y lo pide la std de Rust (que va detrás en el enlace)
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u realpath")
