import 'dart:io';

import 'package:i18n_omatic/i18n_omatic_data.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;

import 'package:i18n_omatic/i18n_omatic_io.dart';

class I18nOMaticGenerator {
  String _srcDir = '';

  String _outDir = '';

  final List<String> _srcFiles = <String>[];

  final List<String> _foundStrings = <String>[];

  final Map<String, String> _translationsFiles = <String, String>{};

  I18nOMaticGenerator(String srcDir, String outDir) {
    _srcDir = srcDir;
    _outDir = outDir;
  }

  List<String> get foundStrings {
    return _foundStrings;
  }

  void _scanSourceFile(String fileName) {
    print('### Scanning file $fileName');

    try {
      final file = File(fileName);
      var contents = file.readAsStringSync();

      var rules = <RegExp>[
        RegExp(r"\.tr\s*\(\s*'(.*?(?<!\\))'"), // TODO to remove
        RegExp(r'\.tr\s*\(\s*"(.*?(?<!\\))"'), // TODO to remove
        RegExp(r"'(.*?(?<!\\))'\s*\.tr\s*\("),
        RegExp(r'"(.*?(?<!\\))"\s*\.tr\s*\('),
      ];

      rules.forEach((rule) {
        Iterable<Match> matches = rule.allMatches(contents);
        matches.forEach((match) {
          if (match.groupCount >= 1 && match.group(1).isNotEmpty) {
            var currentStr = match.group(1);
            // exclude """ and ''' that are not correctly handled yet
            if (currentStr != "'" && currentStr != '"') {
              // replace escape chars associated to quotes
              currentStr =
                  currentStr.replaceAll('\\\"', '\"').replaceAll('\\\'', '\'');
              _foundStrings.add(currentStr);
            }
          }
        });
      });
    } catch (e) {
      print('Error reading file $fileName. Skipped.');
    }
  }

  void addSourceFile(String filePath) {
    _srcFiles.add(filePath);
  }

  void addLang(String langCode, String filePath) {
    _translationsFiles[langCode] = filePath;
  }

  void _updateTranslationFile(String langCode) {
    print('### Updating translation for $langCode');

    I18nOMaticData i18nData;

    print('Loading existing translated strings');

    try {
      i18nData = I18nOMaticIO.loadFromFile(_translationsFiles[langCode]);
    } catch (e) {
      print('Cannot load translations for $langCode.');
    }

    print('Processing strings');
    // move unused to existing if present in found strings
    var unusedKeys = List<String>.from(i18nData.unusedStrings.keys);
    unusedKeys.forEach((value) {
      if (_foundStrings.contains(value) &&
          !i18nData.existingStrings.containsKey(value)) {
        i18nData.existingStrings[value] = i18nData.unusedStrings[value];
        i18nData.unusedStrings.remove(value);
      }
    });

    // move existing to unused if not present in found strings
    var existingKeys = List<String>.from(i18nData.existingStrings.keys);
    existingKeys.forEach((value) {
      if (!_foundStrings.contains(value) &&
          !i18nData.unusedStrings.containsKey(value)) {
        i18nData.unusedStrings[value] = i18nData.existingStrings[value];
        i18nData.existingStrings.remove(value);
      }
    });

    // add found to existing with null value if not present in existing
    _foundStrings.forEach((value) {
      if (!i18nData.existingStrings.containsKey(value)) {
        i18nData.existingStrings[value] = null;
      }
    });

    print(
        'Writing ${i18nData.existingStrings.length} existing strings and ${i18nData.unusedStrings.length} unused strings in translations file');
    try {
      I18nOMaticIO.writeToFile(_translationsFiles[langCode], i18nData);
    } catch (e) {
      print('Cannot write translations for $langCode.');
    }
  }

  void scanSourcesFiles() {
    for (var file in _srcFiles) {
      _scanSourceFile(file);
    }
  }

  void discoverSourcesFiles() {
    final filesToScan = Glob(path.join(_srcDir, '**.dart')).listSync();

    for (var f in filesToScan) {
      addSourceFile(f.path);
    }
  }

  void discoverTranslationsFiles() {
    final filesToScan =
        Glob(path.join(_outDir, I18nOMaticIO.buildFilename('*'))).listSync();

    for (var f in filesToScan) {
      var langCode = path.basenameWithoutExtension(f.path);
      addLang(langCode, f.path);
    }
  }

  void updateTranslationsFiles() {
    _translationsFiles.forEach((key, value) {
      _updateTranslationFile(key);
    });
  }

  void run() {
    discoverSourcesFiles();

    discoverTranslationsFiles();

    scanSourcesFiles();

    updateTranslationsFiles();
  }
}
