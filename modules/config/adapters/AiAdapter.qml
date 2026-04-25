import Quickshell.Io

JsonAdapter {
    property string systemPrompt: "You are a helpful assistant running on a Linux system. You have access to some tools to control the system."
    property string tool: "none"
    property list<var> extraModels: []
    property string defaultModel: "gemini-2.0-flash"
    property int sidebarWidth: 400
    property string sidebarPosition: "right"
    property bool sidebarPinnedOnStartup: false
}
