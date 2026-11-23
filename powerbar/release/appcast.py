# -*- coding: utf-8 -*-
"""appcast.py: maintain an app's Sparkle appcast (python 2.7, no extra modules).

  appcast.py newest FILE
      prints the highest sparkle:version in FILE (0 if FILE is missing or has no items)
  appcast.py add FILE --app NAME --link URL --title T --version N --short V
                 --minos 10.4 --url URL --sig SIG --length BYTES --notes NOTES.html
      adds a release as the first <item> (creating FILE if needed); refuses a version
      that isn't newer than every item already there
"""
import email.utils, os, re, sys
from xml.dom import minidom
from xml.sax.saxutils import escape, quoteattr

SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'


def versions(path):
    if not os.path.exists(path):
        return []
    doc = minidom.parse(path)
    out = []
    for enc in doc.getElementsByTagName('enclosure'):
        v = enc.getAttribute('sparkle:version')
        if v:
            out.append(int(v))
    return out


def newest(path):
    return max(versions(path) or [0])


def opts(args):
    o = {}
    while args:
        k = args.pop(0)
        if not k.startswith('--') or not args:
            sys.exit('appcast.py: bad argument %r' % k)
        o[k[2:]] = args.pop(0)
    need = 'app link title version short minos url sig length notes'.split()
    missing = [n for n in need if n not in o]
    if missing:
        sys.exit('appcast.py: missing --' + ' --'.join(missing))
    return o


def add(path, o):
    if int(o['version']) <= newest(path):
        sys.exit('appcast.py: version %s is not newer than %d' % (o['version'], newest(path)))
    notes = open(o['notes']).read().strip()
    if ']]>' in notes:
        sys.exit('appcast.py: the release notes contain "]]>"')
    for k in ('sig', 'length', 'version'):
        if not re.match(r'^[A-Za-z0-9+/=]+$', o[k]):
            sys.exit('appcast.py: odd --%s %r' % (k, o[k]))
    item = (
        '    <item>\n'
        '      <title>%s</title>\n'
        '      <pubDate>%s</pubDate>\n'
        '      <sparkle:minimumSystemVersion>%s</sparkle:minimumSystemVersion>\n'
        '      <description><![CDATA[\n%s\n      ]]></description>\n'
        '      <enclosure url=%s\n'
        '                 sparkle:version=%s sparkle:shortVersionString=%s\n'
        '                 type="application/octet-stream"\n'
        '                 sparkle:edSignature=%s length=%s />\n'
        '    </item>\n') % (
        escape(o['title']), email.utils.formatdate(usegmt=True), escape(o['minos']), notes,
        quoteattr(o['url']), quoteattr(o['version']), quoteattr(o['short']),
        quoteattr(o['sig']), quoteattr(o['length']))
    if os.path.exists(path):
        text = open(path).read()
    else:
        text = ('<?xml version="1.0" encoding="utf-8"?>\n'
                '<rss version="2.0" xmlns:sparkle="%s">\n'
                '  <channel>\n'
                '    <title>%s</title>\n'
                '    <link>%s</link>\n'
                '    <description>%s updates</description>\n'
                '    <language>en</language>\n'
                '  </channel>\n'
                '</rss>\n') % (SPARKLE_NS, escape(o['app']), escape(o['link']), escape(o['app']))
    at = text.find('    <item>')
    if at < 0:
        at = text.find('  </channel>')
    if at < 0:
        sys.exit('appcast.py: %s has no <channel>' % path)
    text = text[:at] + item + text[at:]
    tmp = path + '.tmp'
    open(tmp, 'w').write(text)
    if versions(tmp)[0] != int(o['version']):   # parses, and the new item comes first
        sys.exit('appcast.py: the new appcast does not read back right (%s)' % tmp)
    os.rename(tmp, path)


if __name__ == '__main__':
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == 'newest':
        print(newest(a[1]))
    elif len(a) > 2 and a[0] == 'add':
        add(a[1], opts(a[2:]))
    else:
        sys.exit(__doc__)
