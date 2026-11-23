/* PowerBar Dashboard widget (Mac OS X 10.4+).
 *
 * Reads ~/Library/Application Support/PowerBar/nowplaying.json (written by the app on
 * every change and every 10 s) while Dashboard is showing, and sends button presses
 * to the app with the bundled powerbar-ctl helper (a distributed notification, so
 * PowerBar stays in the background and Dashboard stays open).
 *
 * Outside Dashboard (the test renderer), "#state=/path/to/dir/" points it at another
 * folder; "#empty" shows the empty look used for Default.png. */

var APP_ID = "io.github.cmstuberg.PowerBar";
var base = null;          /* folder holding nowplaying.json, as a path */
var st = null;            /* last state read */
var readAt = 0;           /* when st was read (ms) */
var pollTimer = null, tickTimer = null;
var artName = null;
var hover = {};

/* ---------- drawing ---------- */

function roundRect (c, x, y, w, h, r) {
    c.beginPath ();
    c.moveTo (x + r, y);
    c.lineTo (x + w - r, y);
    c.quadraticCurveTo (x + w, y, x + w, y + r);
    c.lineTo (x + w, y + h - r);
    c.quadraticCurveTo (x + w, y + h, x + w - r, y + h);
    c.lineTo (x + r, y + h);
    c.quadraticCurveTo (x, y + h, x, y + h - r);
    c.lineTo (x, y + r);
    c.quadraticCurveTo (x, y, x + r, y);
    c.closePath ();
}

function drawChrome () {
    var c = document.getElementById ("chrome").getContext ("2d");
    c.clearRect (0, 0, 330, 124);
    /* soft drop shadow */
    c.save ();
    c.shadowColor = "rgba(0,0,0,0.55)";
    c.shadowBlur = 8;
    c.shadowOffsetY = 2;
    roundRect (c, 8, 6, 314, 108, 14);
    c.fillStyle = "#15181f";
    c.fill ();
    c.restore ();
    /* smoked glass */
    var g = c.createLinearGradient (0, 6, 0, 114);
    g.addColorStop (0, "#3a404d");
    g.addColorStop (0.5, "#1d2129");
    g.addColorStop (1, "#0b0d11");
    roundRect (c, 8, 6, 314, 108, 14);
    c.fillStyle = g;
    c.fill ();
    /* gloss on the top half */
    c.save ();
    roundRect (c, 9, 7, 312, 52, 13);
    c.clip ();
    var gl = c.createLinearGradient (0, 7, 0, 59);
    gl.addColorStop (0, "rgba(255,255,255,0.20)");
    gl.addColorStop (1, "rgba(255,255,255,0.02)");
    c.fillStyle = gl;
    c.fillRect (9, 7, 312, 52);
    c.restore ();
    /* rim */
    roundRect (c, 8.5, 6.5, 313, 107, 14);
    c.strokeStyle = "rgba(255,255,255,0.28)";
    c.lineWidth = 1;
    c.stroke ();
    /* a blue hairline under the gloss, like the icon */
    c.fillStyle = "rgba(79,143,224,0.35)";
    c.fillRect (22, 112, 286, 1);
}

function drawArt (img) {
    var c = document.getElementById ("art").getContext ("2d");
    c.clearRect (0, 0, 84, 84);
    c.save ();
    roundRect (c, 0, 0, 84, 84, 8);
    c.clip ();
    c.fillStyle = "#0b0d11";
    c.fillRect (0, 0, 84, 84);
    if (img) {
        /* fill the square, cropping the longer side */
        var s = Math.min (img.width, img.height);
        c.drawImage (img, (img.width - s) / 2, (img.height - s) / 2, s, s, 0, 0, 84, 84);
    }
    var g = c.createLinearGradient (0, 0, 0, 42);
    g.addColorStop (0, "rgba(255,255,255,0.22)");
    g.addColorStop (1, "rgba(255,255,255,0)");
    c.fillStyle = g;
    c.fillRect (0, 0, 84, 42);
    c.restore ();
    roundRect (c, 0.5, 0.5, 83, 83, 8);
    c.strokeStyle = "rgba(255,255,255,0.35)";
    c.lineWidth = 1;
    c.stroke ();
}

function loadArt (url) {
    var img = new Image ();
    img.onload = function () { drawArt (img); };
    img.onerror = function () { if (url != "Images/placeholder.png") loadArt ("Images/placeholder.png"); };
    img.src = url;
}

/* icons are drawn in a 28 x 28 box, centred on (14, 14) */
var icons = {
    play: function (c, s) {
        if (s && s.paused === false) {          /* playing: show pause */
            c.fillRect (9, 8, 3.5, 12);
            c.fillRect (15.5, 8, 3.5, 12);
        } else {
            c.beginPath (); c.moveTo (10.5, 7.5); c.lineTo (20, 14); c.lineTo (10.5, 20.5); c.closePath (); c.fill ();
        }
    },
    next: function (c) {
        c.beginPath (); c.moveTo (7, 9); c.lineTo (13, 14); c.lineTo (7, 19); c.closePath (); c.fill ();
        c.beginPath (); c.moveTo (13, 9); c.lineTo (19, 14); c.lineTo (13, 19); c.closePath (); c.fill ();
        c.fillRect (19, 9, 2, 10);
    },
    love: function (c, s) {
        if (s && s.loved) c.fillStyle = "#ff5470";
        c.beginPath ();
        c.moveTo (14, 20.5);
        c.bezierCurveTo (6, 15, 7, 8.5, 10.5, 8.5);
        c.bezierCurveTo (12.5, 8.5, 13.5, 9.8, 14, 11);
        c.bezierCurveTo (14.5, 9.8, 15.5, 8.5, 17.5, 8.5);
        c.bezierCurveTo (21, 8.5, 22, 15, 14, 20.5);
        c.closePath ();
        c.fill ();
    },
    ban: function (c) {                         /* thumbs down: a thumbs up, turned over */
        c.save ();
        c.translate (28, 28);
        c.rotate (Math.PI);
        c.translate (6, 6);
        c.fillRect (0, 7, 3, 8);
        c.beginPath ();
        c.moveTo (4, 8); c.lineTo (4, 15); c.lineTo (11, 15);
        c.quadraticCurveTo (13, 15, 13.3, 13); c.lineTo (14.3, 9);
        c.quadraticCurveTo (14.5, 7, 12.5, 7); c.lineTo (9.3, 7); c.lineTo (9.8, 3.5);
        c.quadraticCurveTo (9.8, 1.2, 8.2, 1.2); c.closePath ();
        c.fill ();
        c.restore ();
    },
    tired: function (c) {                       /* "zZ" */
        c.lineWidth = 1.6;
        c.lineJoin = "round";
        c.beginPath (); c.moveTo (6.5, 13); c.lineTo (11, 13); c.lineTo (6.5, 19); c.lineTo (11, 19); c.stroke ();
        c.lineWidth = 2;
        c.beginPath (); c.moveTo (13, 8); c.lineTo (21, 8); c.lineTo (13, 19); c.lineTo (21, 19); c.stroke ();
    }
};

function drawButton (name) {
    var cv = document.getElementById ("b-" + name);
    var c = cv.getContext ("2d");
    var h = hover[name] || 0;           /* 0 normal, 1 hover, 2 pressed */
    c.clearRect (0, 0, 28, 28);
    var g = c.createLinearGradient (0, 1, 0, 27);
    if (name == "play") {
        g.addColorStop (0, h == 2 ? "#2a5c9b" : h ? "#5d9be6" : "#4a86d1");
        g.addColorStop (1, h == 2 ? "#123056" : "#1b467f");
    } else {
        g.addColorStop (0, h == 2 ? "#2a2e37" : h ? "#5b6273" : "#474d5b");
        g.addColorStop (1, h == 2 ? "#0e1014" : "#1a1d24");
    }
    c.beginPath ();
    c.arc (14, 14, 12.5, 0, Math.PI * 2, false);
    c.fillStyle = g;
    c.fill ();
    c.strokeStyle = "rgba(255,255,255,0.3)";
    c.lineWidth = 1;
    c.stroke ();
    /* gloss */
    c.save ();
    c.beginPath ();
    c.arc (14, 14, 11.5, Math.PI, 0, false);
    c.clip ();
    var gl = c.createLinearGradient (0, 2, 0, 14);
    gl.addColorStop (0, "rgba(255,255,255,0.28)");
    gl.addColorStop (1, "rgba(255,255,255,0.03)");
    c.fillStyle = gl;
    c.fillRect (0, 0, 28, 14);
    c.restore ();
    c.fillStyle = "rgba(255,255,255,0.92)";
    c.strokeStyle = "rgba(255,255,255,0.92)";
    icons[name] (c, st);
}

function drawButtons () {
    var n = ["play", "next", "love", "ban", "tired"];
    for (var i = 0; i < n.length; i++) drawButton (n[i]);
}

/* ---------- state ---------- */

function clock (s) {
    s = Math.max (0, Math.floor (s));
    var m = Math.floor (s / 60), r = s % 60;
    return m + ":" + (r < 10 ? "0" : "") + r;
}

function setText (id, t) {
    var e = document.getElementById (id);
    if (e.innerText != t) e.innerText = t;
}

function showTime () {
    if (!st || !st.total) { setText ("time", ""); document.getElementById ("fill").style.width = "0"; return; }
    /* elapsed was measured when PowerBar wrote the file */
    var el = st.elapsed + (st.paused ? 0 : new Date ().getTime () / 1000 - st.written);
    if (el > st.total) el = st.total;
    setText ("time", "-" + clock (st.total - el));
    document.getElementById ("fill").style.width = Math.round (152 * el / st.total) + "px";
}

function running () {
    /* the app rewrites the file every 10 s; older than 30 s = not running */
    return st && st.running && (new Date ().getTime () / 1000 - st.written) < 30;
}

function render () {
    var on = running ();
    document.getElementById ("playing").style.display = on ? "block" : "none";
    document.getElementById ("idle").style.display = on ? "none" : "block";
    if (!on) {
        if (artName !== "") { artName = ""; loadArt ("Images/placeholder.png"); }
        return;
    }
    setText ("title", st.title || (st.station ? "Tuning in" + "…" : "Signing in" + "…"));
    setText ("artist", st.artist || "");
    setText ("album", st.album || "");
    document.getElementById ("b-love").title = st.loved ? "Loved" : "Love";
    var art = st.art || "";
    if (art != artName) {
        artName = art;
        /* PowerBar alternates two cover file names, and WebKit keeps images it has
         * loaded by URL: song 3's "cover-1" would show song 1's picture. A query that's
         * new for each song (when PowerBar wrote it) makes WebKit read the file again. */
        loadArt (art ? fileURL (base + art) + "?v=" + st.written : "Images/placeholder.png");
    }
    drawButtons ();
    showTime ();
}

function fileURL (path) {
    return "file://" + encodeURI (path).replace (/#/g, "%23");
}

function poll () {
    var x = new XMLHttpRequest ();
    x.onreadystatechange = function () {
        if (x.readyState != 4) return;
        var s = null;
        try { if (x.responseText) s = eval ("(" + x.responseText + ")"); } catch (e) { s = null; }
        st = s;
        readAt = new Date ().getTime ();
        render ();
    };
    try {
        x.open ("GET", fileURL (base + "nowplaying.json"), true);
        x.setRequestHeader ("Cache-Control", "no-cache");
        x.send (null);
    } catch (e) {
        st = null;
        render ();
    }
}

function start () {
    if (pollTimer) return;
    poll ();
    pollTimer = setInterval (poll, 1000);
    tickTimer = setInterval (showTime, 250);
}

function stop () {
    if (pollTimer) clearInterval (pollTimer);
    if (tickTimer) clearInterval (tickTimer);
    pollTimer = tickTimer = null;
}

/* ---------- actions ---------- */

function widgetDir () {
    var p = decodeURI (location.pathname);
    return p.substring (0, p.lastIndexOf ("/"));
}

function send (cmd) {
    if (window.widget)
        widget.system ("'" + widgetDir () + "/powerbar-ctl' " + cmd, function () {});
    /* show it at once; the next read confirms */
    if (st) {
        if (cmd == "playpause") {
            var now = new Date ().getTime () / 1000;
            if (!st.paused) st.elapsed += now - st.written;
            st.paused = !st.paused;
            st.written = now;
        }
        if (cmd == "love") st.loved = true;
    }
    drawButtons ();
    setTimeout (poll, 400);
}

function openApp () {
    if (window.widget) widget.openApplication (APP_ID);
}

function wireButton (name, cmd) {
    var e = document.getElementById ("b-" + name);
    e.onmouseover = function () { hover[name] = 1; drawButton (name); };
    e.onmouseout  = function () { hover[name] = 0; drawButton (name); };
    e.onmousedown = function () { hover[name] = 2; drawButton (name); };
    e.onmouseup   = function () { hover[name] = 1; drawButton (name); };
    e.onclick     = function () { send (cmd); };
}

function setup () {
    drawChrome ();
    wireButton ("play", "playpause");
    wireButton ("next", "next");
    wireButton ("love", "love");
    wireButton ("ban", "ban");
    wireButton ("tired", "tired");
    drawButtons ();
    loadArt ("Images/placeholder.png");
    artName = "";

    var m = /state=([^&]+)/.exec (location.hash);
    if (m) {
        base = decodeURIComponent (m[1]);
    } else if (window.widget) {
        var home = widget.system ("/usr/bin/printenv HOME", null).outputString.replace (/\s+$/, "");
        base = home + "/Library/Application Support/PowerBar/";
    }
    if (location.hash == "#empty") {          /* Default.png: chrome, art, buttons only */
        document.getElementById ("idle").style.display = "none";
        document.getElementById ("playing").style.display = "block";
        return;
    }
    if (window.widget) {
        widget.onshow = start;
        widget.onhide = stop;
    }
    if (base) start ();
}
