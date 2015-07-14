/*
 * Copyright (C) 2014-2015 Canonical, Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors: Michael Zanetti <michael.zanetti@canonical.com>
 */

import QtQuick 2.3
import QtQuick.Layouts 1.1
import Ubuntu.Components 1.1
import Unity.Application 0.1
import "../Components/PanelState"
import Utils 0.1
import Ubuntu.Gestures 0.1

Rectangle {
    id: root

    anchors.fill: parent

    // Controls to be set from outside
    property int dragAreaWidth // just to comply with the interface shared between stages
    property real maximizedAppTopMargin
    property bool interactive
    property bool spreadEnabled // just to comply with the interface shared between stages
    property real inverseProgress: 0 // just to comply with the interface shared between stages
    property int shellOrientationAngle: 0
    property int shellOrientation
    property int shellPrimaryOrientation
    property int nativeOrientation
    property bool beingResized: false

    // functions to be called from outside
    function updateFocusedAppOrientation() { /* TODO */ }
    function updateFocusedAppOrientationAnimated() { /* TODO */}

    // To be read from outside
    readonly property var mainApp: ApplicationManager.focusedApplicationId
            ? ApplicationManager.findApplication(ApplicationManager.focusedApplicationId)
            : null
    property int mainAppWindowOrientationAngle: 0
    readonly property bool orientationChangesEnabled: false

    property alias background: wallpaper.source
    property bool altTabPressed: false

    CrossFadeImage {
        id: wallpaper
        anchors.fill: parent
        sourceSize { height: root.height; width: root.width }
        fillMode: Image.PreserveAspectCrop
    }

    Connections {
        target: ApplicationManager
        onApplicationAdded: {
            ApplicationManager.requestFocusApplication(appId)
        }

        onFocusRequested: {
            var appIndex = priv.indexOf(appId);
            var appDelegate = appRepeater.itemAt(appIndex);
            if (appDelegate.state === "minimized") {
                appDelegate.state = "normal"
            }
            ApplicationManager.focusApplication(appId);
        }
    }

    QtObject {
        id: priv

        readonly property string focusedAppId: ApplicationManager.focusedApplicationId
        readonly property var focusedAppDelegate: {
            var index = indexOf(focusedAppId);
            return index >= 0 && index < appRepeater.count ? appRepeater.itemAt(index) : null
        }

        onFocusedAppDelegateChanged: {
            if (focusedAppDelegate) {
                focusedAppDelegate.focus = true;
            }
        }

        function indexOf(appId) {
            for (var i = 0; i < ApplicationManager.count; i++) {
                if (ApplicationManager.get(i).appId == appId) {
                    return i;
                }
            }
            return -1;
        }
    }

    Connections {
        target: PanelState
        onClose: {
            ApplicationManager.stopApplication(ApplicationManager.focusedApplicationId)
        }
        onMinimize: appRepeater.itemAt(0).state = "minimized"
        onMaximize: appRepeater.itemAt(0).state = "normal"
    }

    Binding {
        target: PanelState
        property: "buttonsVisible"
        value: priv.focusedAppDelegate !== null && priv.focusedAppDelegate.state === "maximized"
    }

    Rectangle {
        id: spreadBackground
        anchors.fill: parent
        color: "#55000000"
        visible: false
    }

    FocusScope {
        id: appContainer
        anchors.fill: parent

        Keys.onPressed: {
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_Backtab:
                selectPrevious(event.isAutoRepeat)
                break;
            case Qt.Key_Right:
            case Qt.Key_Tab:
                selectNext(event.isAutoRepeat)
                break;
            case Qt.Key_Escape:
                appRepeater.highlightedIndex = -1
            case Qt.Key_Enter:
            case Qt.Key_Return:
            case Qt.Key_Space:
                root.state = ""
            }
        }

        function selectNext(isAutoRepeat) {
            if (isAutoRepeat && appRepeater.highlightedIndex >= ApplicationManager.count -1) {
                return; // AutoRepeat is not allowed to wrap around
            }

            appRepeater.highlightedIndex = (appRepeater.highlightedIndex + 1) % ApplicationManager.count;
            var newContentX = ((spreadFlickable.contentWidth) / (ApplicationManager.count + 1)) * Math.max(0, Math.min(ApplicationManager.count - 5, appRepeater.highlightedIndex - 3));
            if (spreadFlickable.contentX < newContentX || appRepeater.highlightedIndex == 0) {
                spreadFlickable.snapTo(newContentX)
            }
        }

        function selectPrevious(isAutoRepeat) {
            if (isAutoRepeat && appRepeater.highlightedIndex == 0) {
                return; // AutoRepeat is not allowed to wrap around
            }

            var newIndex = appRepeater.highlightedIndex - 1 >= 0 ? appRepeater.highlightedIndex - 1 : ApplicationManager.count - 1;
            appRepeater.highlightedIndex = newIndex;
            var newContentX = ((spreadFlickable.contentWidth) / (ApplicationManager.count + 1)) * Math.max(0, Math.min(ApplicationManager.count - 5, appRepeater.highlightedIndex - 1));
            if (spreadFlickable.contentX > newContentX || newIndex == ApplicationManager.count -1) {
                spreadFlickable.snapTo(newContentX)
            }
        }

        function focusSelected() {
            if (appRepeater.highlightedIndex != -1) {
                appRepeater.itemAt(appRepeater.highlightedIndex).focus = true;
            }
        }

        Repeater {
            id: appRepeater
            model: ApplicationManager
            objectName: "appRepeater"

            property int highlightedIndex: -1
            property int closingIndex: -1

            delegate: FocusScope {
                id: appDelegate
                z: ApplicationManager.count - index
                y: units.gu(3)
                width: units.gu(60)
                height: units.gu(50)

                readonly property int minWidth: units.gu(10)
                readonly property int minHeight: units.gu(10)

                onFocusChanged: {
                    if (focus && ApplicationManager.focusedApplicationId !== model.appId) {
                        ApplicationManager.requestFocusApplication(model.appId);
                    }
                }
                Component.onCompleted: {
                    if (ApplicationManager.focusedApplicationId == model.appId) {
                        decoratedWindow.forceActiveFocus();
                    }
                }

                Behavior on x {
                    id: closeBehavior
                    enabled: appRepeater.closingIndex >= 0
                    UbuntuNumberAnimation {
                        onRunningChanged: if (!running) appRepeater.closingIndex = -1
                    }
                }

                states: [
                    State {
                        name: "normal"
                    },
                    State {
                        name: "maximized"
                        PropertyChanges { target: appDelegate; x: 0; y: 0; width: root.width; height: root.height }
                    },
                    State {
                        name: "minimized"
                        PropertyChanges { target: appDelegate; x: -appDelegate.width / 2; scale: units.gu(5) / appDelegate.width; opacity: 0 }
                    },
                    State {
                        name: "altTab"; when: root.state == "altTab" && root.workspacesUpdated
                        PropertyChanges {
                            target: appDelegate
                            x: spreadMaths.animatedX
                            y: spreadMaths.animatedY + (appDelegate.height - decoratedWindow.height)
                            angle: spreadMaths.animatedAngle
                            itemScale: spreadMaths.scale
                            itemScaleOriginY: decoratedWindow.height / 2;
                            z: index
                            visible: spreadMaths.itemVisible
                        }
                        PropertyChanges {
                            target: decoratedWindow
                            decorationShown: false
                            highlightShown: index == appRepeater.highlightedIndex
                            state: "transformed"
                            width: spreadMaths.spreadHeight
                            height: spreadMaths.spreadHeight
                            shadowOpacity: spreadMaths.shadowOpacity
                        }
                        PropertyChanges {
                            target: tileInfo
                            visible: true
                            opacity: spreadMaths.tileInfoOpacity
                        }
                        PropertyChanges {
                            target: spreadSelectArea
                            enabled: true
                        }
                        PropertyChanges {
                            target: windowMoveResizeArea
                            enabled: false
                        }
                    }
                ]
                transitions: [
                    Transition {
                        from: "maximized,minimized,normal,"
                        to: "maximized,minimized,normal,"
                        PropertyAnimation { target: appDelegate; properties: "x,y,opacity,width,height,scale" }
                    }
                ]
                property real angle: 0
                property real itemScale: 1
                property int itemScaleOriginX: 0
                property int itemScaleOriginY: 0

                SpreadMaths {
                    id: spreadMaths
                    flickable: spreadFlickable
                    itemIndex: index
                    totalItems: Math.max(6, ApplicationManager.count)
                    sceneHeight: root.height
                    itemHeight: appDelegate.height
                }

                WindowMoveResizeArea {
                    id: windowMoveResizeArea
                    target: appDelegate
                    minWidth: appDelegate.minWidth
                    minHeight: appDelegate.minHeight
                    resizeHandleWidth: units.gu(2)
                    windowId: model.appId // FIXME: Change this to point to windowId once we have such a thing

                    onPressed: appDelegate.focus = true;
                }

                DecoratedWindow {
                    id: decoratedWindow
                    anchors.left: appDelegate.left
                    anchors.top: appDelegate.top
                    windowWidth: appDelegate.width
                    windowHeight: appDelegate.height
                    application: ApplicationManager.get(index)
                    active: ApplicationManager.focusedApplicationId === model.appId
                    focus: false

                    onClose: ApplicationManager.stopApplication(model.appId)
                    onMaximize: appDelegate.state = (appDelegate.state == "maximized" ? "normal" : "maximized")
                    onMinimize: appDelegate.state = "minimized"

                    transform: [
                        Scale {
                            origin.x: itemScaleOriginX
                            origin.y: itemScaleOriginY
                            xScale: itemScale
                            yScale: itemScale
                        },
                        Rotation {
                            origin { x: 0; y: (decoratedWindow.height - (decoratedWindow.height * itemScale / 2)) }
                            axis { x: 0; y: 1; z: 0 }
                            angle: appDelegate.angle
                        }
                    ]

                    MouseArea {
                        id: spreadSelectArea
                        anchors.fill: parent
                        anchors.margins: -units.gu(2)
                        enabled: false
                        hoverEnabled: enabled

                        // There is a bug in MouseArea where containsMouse doesn't
                        // return to false if the MouseArea is disabled while
                        // containing the mouse. Let's manage the property our own.
                        property bool upperThirdContainsMouse: false
                        onContainsMouseChanged: evaluateContainsMouse()
                        onMouseYChanged: evaluateContainsMouse()
                        function evaluateContainsMouse() {
                            if (containsMouse) {
                                appRepeater.highlightedIndex = index
                            }

                            if (containsMouse && mouseY < height / 3) {
                                spreadSelectArea.upperThirdContainsMouse = true
                            } else {
                                spreadSelectArea.upperThirdContainsMouse = false;
                            }
                        }
                        onEnabledChanged: {
                            if (!enabled) {
                                spreadSelectArea.upperThirdContainsMouse = false
                            }
                        }

                        onClicked: {
                            appDelegate.focus = true
                            root.state = ""
                        }
                    }
                }

                Image {
                    id: closeImage
                    anchors { left: parent.left; top: parent.top; leftMargin: -height / 2; topMargin: -height / 2 + spreadMaths.closeIconOffset }
                    source: "graphics/window-close.svg"
                    visible: spreadSelectArea.upperThirdContainsMouse
                    height: units.gu(1.5)
                    width: height
                    sourceSize.width: width
                    sourceSize.height: height
                }

                MouseArea {
                    id: closeMouseArea
                    objectName: "closeMouseArea"
                    anchors.fill: closeImage
                    anchors.margins: -units.gu(2)
                    enabled: spreadSelectArea.upperThirdContainsMouse
                    onClicked: {
                        print("enabling clsoeBehaviro")
                        appRepeater.closingIndex = index;
                        ApplicationManager.stopApplication(model.appId)
                    }
                }

                ColumnLayout {
                    id: tileInfo
                    width: units.gu(30)
                    anchors { left: parent.left; top: decoratedWindow.bottom; topMargin: units.gu(5) }
                    visible: false
                    spacing: units.gu(1)

                    UbuntuShape {
                        Layout.preferredHeight: Math.min(units.gu(6), root.height * .05)
                        Layout.preferredWidth: height * 8 / 7.6
                        image: Image {
                            anchors.fill: parent
                            source: model.icon
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.preferredHeight: units.gu(6)
                        text: model.name
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                    }
                }
            }
        }
    }

    FloatingFlickable {
        id: spreadFlickable
        anchors.fill: parent
        contentWidth: Math.max(6, ApplicationManager.count) * Math.min(height / 4, width / 5)
        enabled: false

        function snapTo(contentX) {
            snapAnimation.stop();
            snapAnimation.to = contentX
            snapAnimation.start();
        }

        UbuntuNumberAnimation {
            id: snapAnimation
            target: spreadFlickable
            property: "contentX"
        }
    }

    Item {
        id: workspaceSelector
        anchors {
            left: parent.left
            top: parent.top
            right: parent.right
            topMargin: units.gu(3.5) // TODO: should be root.panelHeight
        }
        height: root.height * 0.25
        visible: false

        RowLayout {
            anchors.fill: parent
            spacing: units.gu(1)
            Item { Layout.fillWidth: true }
            Repeater {
                model: 1 // TODO: will be a workspacemodel in the future
                Item {
                    Layout.fillHeight: true
                    Layout.preferredWidth: ((height - units.gu(6)) * root.width / root.height)
                    Image {
                        source: root.background
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        height: parent.height * 0.75

                        // FIXME: This is temporary until we can have multiple Items per surface
                        ShaderEffect {
                            anchors.fill: parent

                            property var source: ShaderEffectSource {
                                id: shaderEffectSource
                                live: false
                                sourceItem: appContainer
                                Connections { target: root; onUpdateWorkspaces: shaderEffectSource.scheduleUpdate() }
                            }

                            fragmentShader: "
                                varying highp vec2 qt_TexCoord0;
                                uniform sampler2D source;
                                void main(void)
                                {
                                    highp vec4 sourceColor = texture2D(source, qt_TexCoord0);
                                    gl_FragColor = sourceColor;
                                }"
                        }
                    }

                    // TODO: This is the bar for the currently selected workspace
                    // Enable this once the workspace stuff is implemented
//                    Rectangle {
//                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
//                        height: units.dp(2)
//                        color: UbuntuColors.orange
//                        visible: index == 0 // TODO: should be active workspace index
//                    }
                }

            }
            // TODO: This is the "new workspace" button. Enable this once workspaces are implemented
//            Item {
//                Layout.fillHeight: true
//                Layout.preferredWidth: ((height - units.gu(6)) * root.width / root.height)
//                Rectangle {
//                    anchors {
//                        left: parent.left
//                        right: parent.right
//                        verticalCenter: parent.verticalCenter
//                    }
//                    height: parent.height * 0.75
//                    color: "#22ffffff"

//                    Label {
//                        anchors.centerIn: parent
//                        font.pixelSize: parent.height / 2
//                        text: "+"
//                    }
//                }
//            }
            Item { Layout.fillWidth: true }
        }
    }

    Label {
        id: currentSelectedLabel
        anchors { bottom: parent.bottom; bottomMargin: root.height * 0.625; horizontalCenter: parent.horizontalCenter }
        text: appRepeater.highlightedIndex >= 0 ? ApplicationManager.get(appRepeater.highlightedIndex).name : ""
        visible: false
        fontSize: "large"
    }

    states: [
        State {
            name: "altTab"; when: root.altTabPressed
            PropertyChanges { target: workspaceSelector; visible: true }
            PropertyChanges { target: spreadFlickable; enabled: true }
            PropertyChanges { target: currentSelectedLabel; visible: true }
            PropertyChanges { target: spreadBackground; visible: true }
            PropertyChanges { target: appContainer; focus: true }
        }
    ]
    signal updateWorkspaces();
    property bool workspacesUpdated: false
    transitions: [
        Transition {
            from: "*"
            to: "altTab"
            SequentialAnimation {
                PropertyAction { target: appRepeater; property: "highlightedIndex"; value: Math.min(ApplicationManager.count - 1, 1) }
                PauseAnimation { duration: 50 }
                PropertyAction { target: workspaceSelector; property: "visible" }
                ScriptAction { script: root.updateWorkspaces() }
                // FIXME: Updating of shaderEffectSource take a bit of time. This is temporary until we can paint multiple items per surface
                PauseAnimation { duration: 10 }
                PropertyAction { target: root; property: "workspacesUpdated"; value: true }
                PropertyAction { target: spreadFlickable; property: "visible" }
                PropertyAction { targets: [currentSelectedLabel,spreadBackground]; property: "visible" }
                PropertyAction { target: spreadFlickable; property: "contentX"; value: 0 }
            }
        },
        Transition {
            from: "*"
            to: "*"
            PropertyAnimation { property: "opacity" }
            PropertyAction { target: root; property: "workspacesUpdated"; value: false }
            ScriptAction { script: { appContainer.focusSelected() } }
            PropertyAction { target: appRepeater; property: "highlightedIndex"; value: -1 }
        }

    ]

    MouseArea {
         anchors {
             top: parent.top
             right: parent.right
             bottom: parent.bottom
         }
         // TODO: Make this a push to edge thing like the launcher when we can,
         // for now, yes, we want 1 pixel, regardless of the scaling
         width: 1
         hoverEnabled: true
         onContainsMouseChanged: {
             if (containsMouse) {
                 root.state = "altTab"
             }
         }
    }
}
