import {buildLocalizationResources} from './localization.js';

export const nativeSwiftSources = [
  'apps/macos/Localization.swift', 'apps/macos/Bridge.swift', 'apps/macos/Model.swift',
  'apps/macos/DocumentView.swift', 'apps/macos/SidecarSheet.swift', 'apps/macos/Views.swift',
  'apps/macos/MappingSheet.swift', 'apps/macos/BundleSheet.swift', 'apps/macos/WorkspaceSplit.swift',
  'apps/macos/WorkbookView.swift', 'apps/macos/App.swift',
] as const;

// Legacy regression probes explicitly exercise Korean UI assumptions; the new
// locale matrix verifies English and live switching independently.
export const nativeLocalizationTestSources = [
  'apps/macos/Localization.swift', 'tests/native/LocalizationTestSupport.swift',
] as const;
export const prepareLegacyNativeLocalization = buildLocalizationResources;
