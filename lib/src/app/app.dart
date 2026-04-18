import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dashboard_page.dart';

class ApkBuildPublishApp extends StatefulWidget {
  const ApkBuildPublishApp({super.key});

  @override
  State<ApkBuildPublishApp> createState() => _ApkBuildPublishAppState();
}

class _ApkBuildPublishAppState extends State<ApkBuildPublishApp> {
  final DashboardPageController _dashboardController =
      DashboardPageController();
  static const String _appMenuLabel = 'APK Build Publish';

  @override
  void dispose() {
    _dashboardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B6E4F),
      brightness: Brightness.light,
    );

    final app = MaterialApp(
      title: 'APK Build Publish',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4EFE6),
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.92),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFCF7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: DashboardPage(controller: _dashboardController),
    );

    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.macOS ||
        !Platform.isMacOS) {
      return app;
    }

    return PlatformMenuBar(
      menus: <PlatformMenuItem>[
        PlatformMenu(
          label: _appMenuLabel,
          menus: <PlatformMenuItem>[
            const PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.about,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.quit,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: '配置',
          menus: <PlatformMenuItem>[
            PlatformMenuItem(
              label: '导入配置',
              onSelected: _dashboardController.importConfigs,
            ),
            PlatformMenuItem(
              label: '导出配置',
              onSelected: _dashboardController.exportConfigs,
            ),
          ],
        ),
      ],
      child: app,
    );
  }
}
