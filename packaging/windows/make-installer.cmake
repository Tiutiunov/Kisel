# Makes KiselSetup-<version>.exe: `cmake --build <build> --target installer`.
#
# The application is installed into a staging folder (the Qt libraries, plugins and QML
# imports next to kisel.exe, and the compiler's runtime DLLs beside them), zipped, and
# the zip is appended to the small setup program (packaging/windows/setup.cpp).
#
#   -DBUILD_DIR=<build> -DSTUB=<kisel-setup.exe> -DVERSION=<x.y.z> -DCONFIG=<Release>
#
# One installer for both kinds of machine: with -DARM_ZIP=<the zip of a build for ARM
# processors> that zip is appended after the first, and after both a line that says how
# long each is ("KISELPK2", then two lengths of sixteen hex digits). The setup program
# installs whichever suits the machine. -DONLY_ZIP=ON stops at the zip: it is how a
# build for ARM hands its application over (build/installer/payload.zip).
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
file(GLOB redists "${stage}/bin/vc_redist.*.exe")
if(redists)
    file(REMOVE ${redists})
endif()
# (Qt's own translations of its dialogs: Kisel shows none of those, and has its words in Tr.qml)
file(GLOB qms "${stage}/translations/*.qm")
if(qms)
    file(REMOVE ${qms})
endif()
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

if(ONLY_ZIP)
    file(SIZE "${zip}" bytes)
    math(EXPR mb "${bytes} / 1048576")
    message(STATUS "Payload: ${zip} (${mb} MB)")
    return()
endif()

file(TO_NATIVE_PATH "${STUB}" stub_n)
file(TO_NATIVE_PATH "${zip}" zip_n)
file(TO_NATIVE_PATH "${out}" out_n)
if(ARM_ZIP AND EXISTS "${ARM_ZIP}")
    # (a length as sixteen hex digits)
    function(hex16 number var)
        math(EXPR h "${number}" OUTPUT_FORMAT HEXADECIMAL)
        string(SUBSTRING "${h}" 2 -1 h)
        string(LENGTH "${h}" n)
        math(EXPR pad "16 - ${n}")
        string(REPEAT "0" ${pad} zeros)
        set(${var} "${zeros}${h}" PARENT_SCOPE)
    endfunction()
    file(SIZE "${zip}" plain_len)
    file(SIZE "${ARM_ZIP}" arm_len)
    hex16(${plain_len} plain_hex)
    hex16(${arm_len} arm_hex)
    set(tail "${BUILD_DIR}/installer/tail.txt")
    file(WRITE "${tail}" "KISELPK2${plain_hex}${arm_hex}")
    file(TO_NATIVE_PATH "${ARM_ZIP}" arm_n)
    file(TO_NATIVE_PATH "${tail}" tail_n)
    execute_process(COMMAND cmd /c copy /b /y "${stub_n}" + "${zip_n}" + "${arm_n}" + "${tail_n}" "${out_n}" RESULT_VARIABLE rc OUTPUT_QUIET)
    set(what "both kinds of processor")
else()
    execute_process(COMMAND cmd /c copy /b /y "${stub_n}" + "${zip_n}" "${out_n}" RESULT_VARIABLE rc OUTPUT_QUIET)
    set(what "ordinary processors only")
endif()
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "joining the installer failed (${rc})")
endif()
file(SIZE "${out}" bytes)
math(EXPR mb "${bytes} / 1048576")
message(STATUS "Installer: ${out} (${mb} MB, ${what})")
