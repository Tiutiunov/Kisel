# Makes KiselSetup-<version>.exe: `cmake --build <build> --target installer`.
#
# The application is installed into a staging folder (the Qt libraries, plugins and QML
# imports next to kisel.exe, and the compiler's runtime DLLs beside them), zipped, and
# the zip is appended to the small setup program (packaging/windows/setup.cpp).
#
#   -DBUILD_DIR=<build> -DSTUB=<kisel-setup.exe> -DVERSION=<x.y.z> -DCONFIG=<Release>
set(stage "${BUILD_DIR}/installer/stage")
set(zip "${BUILD_DIR}/installer/payload.zip")
set(out "${BUILD_DIR}/KiselSetup-${VERSION}.exe")

file(REMOVE_RECURSE "${BUILD_DIR}/installer")
file(MAKE_DIRECTORY "${stage}")
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BUILD_DIR}" --prefix "${stage}" --config "${CONFIG}"
    RESULT_VARIABLE rc OUTPUT_QUIET)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "cmake --install failed (${rc})")
endif()
# (the runtime's own installer is not needed: its DLLs are installed next to the app)
file(REMOVE "${stage}/bin/vc_redist.x64.exe")
# What the deploy tool brings along and Kisel never loads: the shader compiler of
# Direct3D 12 (Kisel draws with Direct3D 11), the QML debugger's plugins, a touch
# protocol nobody speaks to it.
file(REMOVE "${stage}/bin/dxcompiler.dll" "${stage}/bin/dxil.dll")
file(REMOVE_RECURSE "${stage}/plugins/qmltooling" "${stage}/plugins/generic")
if(NOT EXISTS "${stage}/bin/kisel.exe")
    message(FATAL_ERROR "no kisel.exe in ${stage}/bin")
endif()

file(GLOB parts RELATIVE "${stage}" "${stage}/*")
execute_process(COMMAND "${CMAKE_COMMAND}" -E tar cf "${zip}" --format=zip -- ${parts}
    WORKING_DIRECTORY "${stage}" RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "zipping failed (${rc})")
endif()

file(TO_NATIVE_PATH "${STUB}" stub_n)
file(TO_NATIVE_PATH "${zip}" zip_n)
file(TO_NATIVE_PATH "${out}" out_n)
execute_process(COMMAND cmd /c copy /b /y "${stub_n}" + "${zip_n}" "${out_n}" RESULT_VARIABLE rc OUTPUT_QUIET)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "joining the installer failed (${rc})")
endif()
file(SIZE "${out}" bytes)
math(EXPR mb "${bytes} / 1048576")
message(STATUS "Installer: ${out} (${mb} MB)")
