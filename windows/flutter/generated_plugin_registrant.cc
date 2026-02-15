//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_ble_peripheral/flutter_ble_peripheral_plugin_c_api.h>
#include <flutter_bluetooth_classic_serial/flutter_bluetooth_classic_plugin.h>
#include <permission_handler_windows/permission_handler_windows_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterBlePeripheralPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterBlePeripheralPluginCApi"));
  FlutterBluetoothClassicPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterBluetoothClassicPlugin"));
  PermissionHandlerWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PermissionHandlerWindowsPlugin"));
}
