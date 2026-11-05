import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/opds_client.dart';

const _navigationFeed = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <title>My Library</title>
  <id>urn:root</id>
  <link rel="self" href="/opds" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  <link rel="search" type="application/opensearchdescription+xml" href="/opds/search"/>
  <entry>
    <title>All Series</title>
    <id>urn:all-series</id>
    <link rel="subsection" href="/opds/series" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
    <content type="text">Browse all series</content>
  </entry>
  <entry>
    <title>Latest</title>
    <id>urn:latest</id>
    <link rel="subsection" href="/opds/latest" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
    <content type="text">Recently added</content>
  </entry>
</feed>''';

const _acquisitionFeed = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <title>All Series</title>
  <id>urn:all-series</id>
  <link rel="self" href="/opds/series"/>
  <link rel="next" href="/opds/series?page=2"/>
  <entry>
    <title>Batman (2016)</title>
    <id>urn:series:batman-2016</id>
    <link rel="http://opds-spec.org/image/thumbnail" href="/series/batman-2016/thumbnail"/>
    <link rel="subsection" href="/opds/series/batman-2016" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
    <content type="text">50 issues</content>
  </entry>
  <entry>
    <title>Saga</title>
    <id>urn:series:saga</id>
    <link rel="http://opds-spec.org/image/thumbnail" href="/series/saga/thumbnail"/>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/series/saga/001.cbz" type="application/x-cbz"/>
    <content type="text">54 issues</content>
  </entry>
</feed>''';

const _issuesFeed = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <title>Batman (2016)</title>
  <id>urn:series:batman-2016</id>
  <entry>
    <title>Batman 001</title>
    <id>urn:comic:batman-001</id>
    <link rel="http://opds-spec.org/image/thumbnail" href="/comics/batman-001/thumbnail"/>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/comics/batman-001/file.cbz" type="application/x-cbz"/>
  </entry>
  <entry>
    <title>Batman 002</title>
    <id>urn:comic:batman-002</id>
    <link rel="http://opds-spec.org/image/thumbnail" href="/comics/batman-002/thumbnail"/>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/comics/batman-002/file.cbz" type="application/x-cbz"/>
  </entry>
</feed>''';

void main() {
  group('SSRF protection', () {
    test('rejects private IP in resolved URL', () {
      expect(() => OPDSClient.validateUrl('http://192.168.1.1/feed'), throwsA(isA<ArgumentError>()));
      expect(() => OPDSClient.validateUrl('http://10.0.0.1/feed'), throwsA(isA<ArgumentError>()));
      expect(() => OPDSClient.validateUrl('http://172.16.0.1/feed'), throwsA(isA<ArgumentError>()));
      expect(() => OPDSClient.validateUrl('http://169.254.1.1/feed'), throwsA(isA<ArgumentError>()));
      expect(() => OPDSClient.validateUrl('http://127.0.0.1/feed'), throwsA(isA<ArgumentError>()));
    });

    test('allows public IPs and domains', () {
      OPDSClient.validateUrl('https://opds.example.com/feed');
      OPDSClient.validateUrl('http://203.0.113.1/feed');
    });
  });

  group('OPDSParser', () {
    test('parses navigation feed entries', () {
      final feed = OPDSParser.parseFeed(_navigationFeed);
      expect(feed.title, 'My Library');
      expect(feed.entries.length, 2);
      expect(feed.entries[0].title, 'All Series');
      expect(feed.entries[0].navigationLink, '/opds/series');
      expect(feed.entries[1].title, 'Latest');
      expect(feed.searchUrl, '/opds/search');
    });

    test('parses acquisition feed with next link', () {
      final feed = OPDSParser.parseFeed(_acquisitionFeed);
      expect(feed.title, 'All Series');
      expect(feed.nextUrl, '/opds/series?page=2');
      expect(feed.entries.length, 2);
    });

    test('parses entry thumbnail URL', () {
      final feed = OPDSParser.parseFeed(_acquisitionFeed);
      expect(feed.entries[0].thumbnailUrl, '/series/batman-2016/thumbnail');
    });

    test('parses entry acquisition link', () {
      final feed = OPDSParser.parseFeed(_acquisitionFeed);
      // First entry has subsection (series), no direct acquisition
      expect(feed.entries[0].acquisitionUrl, isNull);
      expect(feed.entries[0].navigationLink, '/opds/series/batman-2016');
      // Second entry has direct acquisition
      expect(feed.entries[1].acquisitionUrl, '/series/saga/001.cbz');
    });

    test('parses issues feed with acquisition links', () {
      final feed = OPDSParser.parseFeed(_issuesFeed);
      expect(feed.entries.length, 2);
      expect(feed.entries[0].title, 'Batman 001');
      expect(feed.entries[0].acquisitionUrl, '/comics/batman-001/file.cbz');
      expect(feed.entries[1].acquisitionUrl, '/comics/batman-002/file.cbz');
    });

    test('handles missing optional fields gracefully', () {
      const minimal = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Test</title>
  <id>urn:test</id>
  <entry>
    <title>Item</title>
    <id>urn:item</id>
  </entry>
</feed>''';
      final feed = OPDSParser.parseFeed(minimal);
      expect(feed.title, 'Test');
      expect(feed.entries.length, 1);
      expect(feed.entries[0].thumbnailUrl, isNull);
      expect(feed.entries[0].acquisitionUrl, isNull);
      expect(feed.entries[0].navigationLink, isNull);
      expect(feed.searchUrl, isNull);
      expect(feed.nextUrl, isNull);
    });
  });
}
