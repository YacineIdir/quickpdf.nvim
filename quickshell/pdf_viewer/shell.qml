import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root

    property string pdfPath: ""
    property int page: 1
    // Target render width in px. nvim computes it (kitty width * zoom) so the
    // result never depends on when the compositor configures this window.
    property int targetWidth: 900
    // Render cache of this daemon, set by the Neovim instance that spawned
    // it (one daemon per instance, ADR 0002). The fallback serves a daemon
    // started by hand.
    property string cacheDir: Quickshell.env("QUICKPDF_CACHE_DIR") || "/tmp/quickshell-pdf-cache"

    // Setting `running = true` on an already-running Process is a no-op, so
    // rapid n/n/z/z presses would drop renders. Mark dirty and re-run on exit.
    property bool renderPending: false
    property real viewRatioX: 0.5
    property real viewRatioY: 0

    // Commands of the render in progress that have not run yet.
    property var renderSteps: []

    // A render is a few programs run one after another, each given as an
    // argument list. No shell ever sees the PDF path, so quotes, spaces and
    // `$(...)` in a file name stay plain characters.
    function renderPage(): void {
        if (root.pdfPath === "")
            return;
        if (renderProc.running) {
            root.renderPending = true;
            return;
        }

        const page = String(root.page);
        const next = root.cacheDir + "/next";
        root.renderSteps = [
            ["mkdir", "-p", root.cacheDir],
            ["pdftoppm", "-png", "-singlefile", "-f", page, "-l", page,
                "-scale-to-x", String(Math.max(100, root.targetWidth)), "-scale-to-y", "-1",
                root.pdfPath, next],
            // Rename, so the Image never loads a half-written page.png.
            ["mv", "-f", next + ".png", root.cacheDir + "/page.png"]
        ];
        root.runNextStep();
    }

    function runNextStep(): void {
        const steps = root.renderSteps;
        root.renderSteps = steps.slice(1);
        renderProc.command = steps[0];
        renderProc.running = true;
    }

    Process {
        id: renderProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && root.renderSteps.length > 0) {
                root.runNextStep();
                return;
            }
            root.renderSteps = [];
            // Remember where the viewport is (as a ratio) so a zoom re-render
            // keeps the same region on screen instead of snapping to the corner.
            const maxX = flick.contentWidth - flick.width;
            const maxY = flick.contentHeight - flick.height;
            root.viewRatioX = maxX > 0 ? flick.contentX / maxX : 0.5;
            root.viewRatioY = maxY > 0 ? flick.contentY / maxY : 0;
            img.source = "";
            img.source = "file://" + root.cacheDir + "/page.png?t=" + Date.now();
            if (root.renderPending) {
                root.renderPending = false;
                root.renderPage();
            }
        }
    }

    IpcHandler {
        target: "pdf"

        function open(path: string, p: int, w: int): void {
            root.pdfPath = path;
            root.page = p;
            root.targetWidth = w;
            win.visible = true;
            root.renderPage();
        }

        function gotoPage(p: int, w: int): void {
            root.page = p;
            root.targetWidth = w;
            root.renderPage();
        }

        function close(): void {
            win.visible = false;
        }

        function pan(dx: int, dy: int): void {
            flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX + dx));
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy));
        }

        function quit(): void {
            Qt.quit();
        }

        function info(): string {
            return win.width + "x" + win.height + " page=" + root.page + " target=" + root.targetWidth + " img=" + img.sourceSize.width + " view=" + Math.round(flick.contentX) + "," + Math.round(flick.contentY);
        }
    }

    FloatingWindow {
        id: win
        title: "quickshell-pdf-viewer"
        visible: false
        color: "#11111b"
        implicitWidth: 900
        implicitHeight: 700

        // The page is rendered by pdftoppm at exactly win.width * scale px,
        // so showing it at its natural size IS the zoom. Flickable pans
        // when it overflows; centred when it is smaller than the window.
        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            contentWidth: Math.max(width, img.width)
            contentHeight: Math.max(height, img.height)
            boundsBehavior: Flickable.StopAtBounds

            Image {
                id: img
                width: sourceSize.width
                height: sourceSize.height
                x: Math.max(0, (flick.width - width) / 2)
                y: Math.max(0, (flick.height - height) / 2)
                cache: false
                asynchronous: true
                onStatusChanged: {
                    if (status !== Image.Ready)
                        return;
                    // contentWidth/Height bindings settle after this signal;
                    // restoring synchronously gets clamped back to 0.
                    Qt.callLater(() => {
                        flick.contentX = Math.max(0, (flick.contentWidth - flick.width) * root.viewRatioX);
                        flick.contentY = Math.max(0, (flick.contentHeight - flick.height) * root.viewRatioY);
                    });
                }
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 6
            color: "#cdd6f4"
            font.pixelSize: 13
            text: "Page " + root.page
        }
    }
}
