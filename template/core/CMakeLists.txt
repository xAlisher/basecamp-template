# --- Logos SDK path resolution ---
# Priority: environment variable (from nix develop) > hardcoded fallback
#
# After running `nix develop`, find your paths:
#   echo $LOGOS_CPP_SDK_ROOT
#   echo $LOGOS_LIBLOGOS_HEADERS
# Then update the fallback paths below for your machine.

if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
    set(LOGOS_CPP_SDK "$ENV{LOGOS_CPP_SDK_ROOT}")
else()
    # TODO: Replace with your Nix store path after first `nix develop`
    set(LOGOS_CPP_SDK "/nix/store/XXXXXXXX-logos-cpp-sdk")
    message(WARNING "Using hardcoded LOGOS_CPP_SDK path. Set LOGOS_CPP_SDK_ROOT env var or update this path.")
endif()

if(DEFINED ENV{LOGOS_LIBLOGOS_HEADERS})
    set(LOGOS_LIBLOGOS_HEADERS "$ENV{LOGOS_LIBLOGOS_HEADERS}")
else()
    # TODO: Replace with your Nix store path after first `nix develop`
    set(LOGOS_LIBLOGOS_HEADERS "/nix/store/XXXXXXXX-logos-liblogos-headers/include")
    message(WARNING "Using hardcoded LOGOS_LIBLOGOS_HEADERS path. Set the env var or update this path.")
endif()

# --- Plugin sources ---

set(PLUGIN_SOURCES
    MyPlugin.h
    MyPlugin.cpp
)

# Copy metadata to build dir (MOC resolves FILE paths relative to build dir)
configure_file(
    plugin_metadata.json
    ${CMAKE_CURRENT_BINARY_DIR}/plugin_metadata.json
    COPYONLY
)

# --- Build MODULE library (not SHARED — Qt plugins require MODULE) ---

add_library(mymodule_plugin MODULE ${PLUGIN_SOURCES})

set_target_properties(mymodule_plugin PROPERTIES
    PREFIX ""                    # Output: mymodule_plugin.so (no "lib" prefix)
    OUTPUT_NAME "mymodule_plugin"
    BUILD_RPATH "$ORIGIN"        # Find bundled deps relative to .so
    INSTALL_RPATH "$ORIGIN"
)

# --- Include paths ---

target_include_directories(mymodule_plugin PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    "${LOGOS_LIBLOGOS_HEADERS}"
    "${LOGOS_CPP_SDK}/include"
    "${LOGOS_CPP_SDK}/include/cpp"
    "${LOGOS_CPP_SDK}/include/core"
)

# --- Link dependencies ---

target_link_libraries(mymodule_plugin PRIVATE
    Qt6::Core
    "${LOGOS_CPP_SDK}/lib/liblogos_sdk.a"
)

# Link libsodium if found (remove if not needed)
if(TARGET PkgConfig::sodium)
    target_link_libraries(mymodule_plugin PRIVATE PkgConfig::sodium)
    target_compile_definitions(mymodule_plugin PRIVATE HAS_LIBSODIUM)
endif()

# --- Install ---

set(LOGOS_APP_DATA "$ENV{HOME}/.local/share/Logos/LogosBasecamp")
set(MODULE_DIR "${LOGOS_APP_DATA}/modules/mymodule")

# Clean stale backups before install (Logos creates .bak copies)
install(CODE "
    set(_modules_dir \"${LOGOS_APP_DATA}/modules\")
    file(GLOB _old \"\${_modules_dir}/mymodule.*\")
    foreach(_dir \${_old})
        message(STATUS \"Removing old module backup: \${_dir}\")
        file(REMOVE_RECURSE \"\${_dir}\")
    endforeach()
")

install(TARGETS mymodule_plugin
    LIBRARY DESTINATION "${MODULE_DIR}"
)

install(FILES manifest.json
    DESTINATION "${MODULE_DIR}"
)
