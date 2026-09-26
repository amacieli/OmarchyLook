import QtQuick
import QtQuick.Window

Window {
    width: 640
    height: 480
    visible: true
    title: "Test"
    color: "black"
    
    Text {
        text: "Hello Qt 6"
        anchors.centerIn: parent
        color: "white"
    }
}
