cmake_minimum_required(VERSION 3.21)
project(Kisel VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Network Widgets Test)

# Optional KDE integration. Each one degrades gracefully when missing.
find_package(LayerShellQt QUIET)
find_package(KF6StatusNotifierItem QUIET)
find_package(KF6Wallet QUIET)

# ---- core: everything that is not UI glue, so tests can link it -------------
add_library(kisel_core STATIC
    src/core/AgentHub.cpp
    src/core/ChatClient.cpp
    src/core/GitHubClient.cpp
    src/core/HookInstaller.cpp
    src/core/HookServer.cpp
    src/core/Preferences.cpp
    src/core/Secrets.cpp
    src/core/SessionModel.cpp
)
target_include_directories(kisel_core PUBLIC src/core)
target_link_libraries(kisel_core PUBLIC Qt6::Core Qt6::Gui Qt6::Network)
target_compile_definitions(kisel_core PUBLIC
    KISEL_VERSION="${PROJECT_VERSION}"
    KISEL_HOOK_BASENAME="kisel-hook")
if(MSVC)
    set(KISEL_WARNINGS /W4)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
else()
    set(KISEL_WARNINGS -Wall -Wextra)
endif()
target_compile_options(kisel_core PUBLIC ${KISEL_WARNINGS})
if(WIN32)
    target_link_libraries(kisel_core PUBLIC advapi32) # Credential Manager, token SID
endif()
if(KF6Wallet_FOUND)
    target_link_libraries(kisel_core PUBLIC KF6::Wallet)
    target_compile_definitions(kisel_core PUBLIC KISEL_WITH_KWALLET)
endif()

# ---- relay: the tiny executable Claude Code runs on every hook event --------
add_executable(kisel-hook hook/main.cpp)
target_link_libraries(kisel-hook PRIVATE Qt6::Core)
target_compile_options(kisel-hook PRIVATE ${KISEL_WARNINGS})
if(WIN32)
    target_link_libraries(kisel-hook PRIVATE advapi32)
endif()

# ---- the app ----------------------------------------------------------------
qt_add_executable(kisel src/app/main.cpp src/app/IslandWindow.cpp src/app/Tray.cpp src/app/Displays.cpp src/app/Sounds.cpp src/app/Launcher.cpp src/app/SeamWindows.cpp src/app/Media.cpp)
# Qt6::Test only feeds the development flag `kisel --drag-test` (synthetic pointer events).
target_link_libraries(kisel PRIVATE kisel_core Qt6::Quick Qt6::QuickControls2 Qt6::Widgets Qt6::Test)
target_compile_options(kisel PRIVATE ${KISEL_WARNINGS})
if(WIN32)
    # No console window; started from a terminal it still prints (IslandWindow::preInit).
    set_target_properties(kisel PROPERTIES WIN32_EXECUTABLE TRUE)
    target_link_libraries(kisel PRIVATE winmm WindowsApp) # PlaySound; the media session (Media.cpp)
endif()
if(LayerShellQt_FOUND)
    target_link_libraries(kisel PRIVATE LayerShellQt::Interface)
    target_compile_definitions(kisel PRIVATE KISEL_WITH_LAYER_SHELL)
endif()
if(KF6StatusNotifierItem_FOUND)
    target_link_libraries(kisel PRIVATE KF6::StatusNotifierItem)
    target_compile_definitions(kisel PRIVATE KISEL_WITH_SNI)
endif()
# The relay is built first and bundled next to the app; the app copies it to
# ~/.local/share/kisel/bin at launch so hooks never point into a build tree.
add_dependencies(kisel kisel-hook)
target_compile_definitions(kisel PRIVATE KISEL_RELAY_NEXT_TO_EXE)

qt_policy(SET QTP0001 NEW) # resource prefix /qt/qml
qt_policy(SET QTP0004 NEW)
set_source_files_properties(qml/Theme.qml qml/Sfx.qml qml/Motion.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
# All QML lives in one flat module directory (type names = file names).
file(GLOB KISEL_QML_SOURCES CONFIGURE_DEPENDS qml/*.qml)
foreach(f ${KISEL_QML_SOURCES})
    get_filename_component(n ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${n})
endforeach()
qt_add_qml_module(kisel
    URI Kisel
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/Sfx.qml
        qml/Motion.qml
        qml/Icon.qml
        qml/DrawnCheck.qml
        qml/StatusPill.qml
        qml/PillChip.qml
        qml/PillDisc.qml
        qml/DockZone.qml
        qml/Ripple.qml
        qml/Seam.qml
        qml/HoldRing.qml
        qml/Neck.qml
        qml/PillBars.qml
        qml/PillDots.qml
        qml/GitHubMark.qml
        qml/LaunchTile.qml
        qml/DotWave.qml
        qml/Spinner.qml
        qml/KToggle.qml
        qml/KSlider.qml
        qml/PlayGlyph.qml
        qml/Spark.qml
        qml/DoneChip.qml
        qml/BarPlayer.qml
        qml/PlayerView.qml
        qml/KField.qml
        qml/Mascot.qml
        qml/StatusBadge.qml
        qml/KButton.qml
        qml/CodePanel.qml
        qml/BrandShape.qml
        qml/Assembly.qml
        qml/DoneBurst.qml
        qml/AttentionTab.qml
        qml/JellyTrio.qml
        qml/HomeBackdrop.qml
        qml/Toast.qml
        qml/ViewHost.qml
        qml/RollText.qml
        qml/GitHubView.qml
        qml/Island.qml
        qml/HomeView.qml
        qml/SessionView.qml
        qml/PermissionView.qml
        qml/ChatView.qml
        qml/SettingsView.qml
    RESOURCES
        resources/fonts/fredoka-latin-600-normal.ttf
        resources/fonts/fredoka-latin-700-normal.ttf
        resources/fonts/nunito-latin-400-normal.ttf
        resources/fonts/nunito-latin-600-normal.ttf
        resources/fonts/nunito-latin-800-normal.ttf
        resources/fonts/jetbrains-mono-latin-400-normal.ttf
        resources/logo/kisel-mark.svg
        resources/logo/kisel-mini.svg
        resources/logo/miku-mini.svg
        resources/sounds/open.wav
        resources/sounds/close.wav
        resources/sounds/click.wav
        resources/sounds/send.wav
        resources/sounds/receive.wav
        resources/sounds/done.wav
        resources/sounds/alert.wav
        resources/sounds/deny.wav
        resources/sounds/dizzy.wav
        resources/sounds/hover.wav
)

# ---- tests ------------------------------------------------------------------
enable_testing()
add_executable(test_core tests/test_core.cpp)
target_link_libraries(test_core PRIVATE kisel_core Qt6::Test)
add_test(NAME core COMMAND test_core)

install(TARGETS kisel kisel-hook RUNTIME DESTINATION bin)
if(WIN32)
    # `cmake --install build --prefix dist` leaves a folder that runs anywhere:
    # the Qt libraries, plugins and QML imports next to kisel.exe.
    qt_generate_deploy_qml_app_script(TARGET kisel OUTPUT_SCRIPT KISEL_DEPLOY_SCRIPT NO_UNSUPPORTED_PLATFORM_ERROR)
    install(SCRIPT ${KISEL_DEPLOY_SCRIPT})
else()
    install(FILES packaging/kisel.desktop DESTINATION share/applications)
endif()
