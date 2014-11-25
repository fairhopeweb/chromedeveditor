// Copyright (c) 2013, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark_polymer.ui;

import 'dart:async';
import 'dart:html';

import 'package:polymer/polymer.dart';
import 'package:spark_widgets/common/spark_widget.dart';
import 'package:spark_widgets/spark_split_view/spark_split_view.dart';

import 'spark_model.dart';
import 'lib/event_bus.dart';
import 'lib/filesystem.dart';
import 'lib/platform_info.dart';
import 'lib/spark_flags.dart';

@CustomTag('spark-polymer-ui')
class SparkPolymerUI extends SparkWidget {
  SparkModel _model;

  // Just some value to start with in case the client doesn't provide it on
  // startup.
  @published int splitViewPosition = 100;

  // NOTE: The initial values for these have to be such that dependent
  // <template if> blocks in the .html are turned on, because the app
  // uses [querySelector] upon startup to find elements in those blocks.
  // The values are later set to their actual values in [refreshFromModel].
  @observable bool liveDeployMode = true;
  @observable bool developerMode = true;
  @observable bool apkBuildMode = true;
  @observable bool polymerDesigner = true;
  @observable bool chromeOS = false;
  @observable String appVersion = '';
  // This flag is different from the rest: the comment immediately above doesn't
  // apply to it, because nothing in the app code depends on the chunks of HTML
  // that it controls, so it doesn't have to be on at start-up time in order to
  // not break the app.
  @observable bool showWipProjectTemplates = false;

  SparkSplitView _splitView;
  InputElement _fileFilter;

  SparkPolymerUI.created() : super.created();

  @override
  void ready() {
    // Listen to insertions of new nodes into the top-level <head>, and move
    // which will be Ace-related <style>s and <script>s that Ace dynamically
    // inserts e.g. when the editor theme is changed: move such nodes under
    // our [shadowRoot]. The reason is that Ace was not designed to
    // work as part of a Polymer element, and so always uses the top-level
    // <head>, while our actual Ace instance lives under the CSS-isolated
    // [shadowRoot].
    var observer = new MutationObserver((records, _) =>
        records.forEach((r) => _poachAceStylesAndScripts(r.addedNodes))
    )..observe(
        document.head,
        childList: true,
        attributes: false,
        characterData: false,
        subtree: false,
        attributeOldValue: false,
        characterDataOldValue: false);
  }

  @override
  void domReady() {
    // Poach initial Ace <style>s that Ace inserts before the observer in
    // [ready] starts listening to new node insertions. See the comment in
    // [ready].
    _poachAceStylesAndScripts(document.head.childNodes);
  }

  @override
  void attached() {
    super.attached();

    _splitView = $['splitView'];
    _fileFilter = $['fileFilter'];
  }

  /*
   * Moves any Ace-related <style>s and <script>s in [nodes] from their original
   * parent (which is [document] to this element's [shadowRoot], where the Ace
   * editor's container, which needs them, lives.
   */
  void _poachAceStylesAndScripts(List<Node> nodes) {
    final List<Node> aceNodes = [];
    nodes.forEach((node) {
      if (node is ScriptElement && node.src.contains('ace/src/js') ||
          node is StyleElement && node.id.startsWith('ace') ||
          node is StyleElement && node.innerHtml.contains('ace_')) {
        aceNodes.add(node);
      }
    });
    aceNodes.forEach((node) {
      node.remove();
      shadowRoot.append(node);
    });
  }

  void modelReady(SparkModel model) {
    assert(_model == null);
    _model = model;
    // Changed selection may mean some menu items become disabled.
    _model.eventBus.onEvent(BusEventType.FILES_CONTROLLER__SELECTION_CHANGED)
        .listen(refreshFromModel);
    refreshFromModel();
  }

  void refreshFromModel([_]) {
    // TODO(ussuri): This also could possibly be done using PathObservers.
    developerMode = SparkFlags.developerMode;
    liveDeployMode = SparkFlags.liveDeployMode;
    apkBuildMode = SparkFlags.apkBuildMode;
    showWipProjectTemplates = SparkFlags.showWipProjectTemplates;
    polymerDesigner = SparkFlags.polymerDesigner;
    chromeOS = PlatformInfo.isCros;
    appVersion = _model.appVersion;

    // This propagates external changes down to the enclosed widgets.
    Observable.dirtyCheck();
  }

  void splitViewPositionChanged() {
    // TODO(ussuri): In deployed code, this was critical for correct
    // propagation of the client's changes in [splitViewPosition] to _splitView.
    // Investigate. `targetSizeChanged()` is due to BUG #2252.
    if (IS_DART2JS) {
      _splitView
          ..targetSize = splitViewPosition
          ..targetSizeChanged();
    }
  }

  void onMenuSelected(CustomEvent event, var detail) {
    if (detail['isSelected']) {
      final actionId = detail['value'];
      final action = _model.actionManager.getAction(actionId);
      action.invoke();
    }
  }

  void onThemeMinus(Event e) {
    _model.aceThemeManager.prevTheme(e);
  }

  void onThemePlus(Event e) {
    _model.aceThemeManager.nextTheme(e);
  }

  void onKeysMinus(Event e) {
    _model.aceKeysManager.dec(e);
  }

  void onKeysPlus(Event e) {
    _model.aceKeysManager.inc(e);
  }

  void onFontSmaller(Event e) {
    e.stopPropagation();
    _model.aceFontManager.dec();
  }

  void onFontLarger(Event e) {
    e.stopPropagation();
    _model.aceFontManager.inc();
  }

  void onSplitterUpdate(CustomEvent e, var detail) {
    _model.onSplitViewUpdate(detail['targetSize']);
  }

  void onResetGit() {
    _model.syncPrefs.removeValue(['git-auth-info', 'git-user-info']);
    _model.setGitSettingsResetDoneVisible(true);
  }

  void onClickRootDirectory() {
    fileSystemAccess.chooseNewProjectLocation(false).then((LocationResult res){
      if (res != null) {
        _model.showRootDirectory();
      }
    });
  }

  // TODO(ussuri): Find a better way to achieve this.
  void onResetPreference() {
    Element resultElement = $['preferenceResetResult'];
    resultElement.style.display = 'block';
    resultElement.text = '';
    _model.syncPrefs.clear().then((_) {
      _model.localPrefs.clear();
    }).catchError((e) {
      resultElement.text = 'Error resetting preferences';
    }).then((_) {
      resultElement.text = 'Preferences have been reset - restart Chrome Dev Editor';
    });
  }

  void handleAnchorClick(Event e) {
    e..preventDefault()..stopPropagation();
    AnchorElement anchor = e.target;
    window.open(anchor.href, '_blank');
  }

  void fileFilterKeydownHandler(KeyboardEvent e) {
    if (e.keyCode == KeyCode.ESC) {
      e..preventDefault()..stopPropagation();
      _fileFilter.value = '';
      _updateFileFilterActive(false);
      _model.filterFilesList(null);
    }
  }

  void fileFilterInputHandler(Event e) {
    _updateFileFilterActive(_fileFilter.value.isNotEmpty);
    _model.filterFilesList(_fileFilter.value);
  }

  void _updateFileFilterActive(bool active) {
    _fileFilter.classes.toggle('active', active);
  }
}
