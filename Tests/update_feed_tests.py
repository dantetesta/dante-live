import base64, copy, importlib.util, pathlib, unittest, xml.etree.ElementTree as ET
root=pathlib.Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('feed', root/'packaging/update-feed.py');feed=importlib.util.module_from_spec(spec);spec.loader.exec_module(feed)
class FeedTests(unittest.TestCase):
    def record(self, version='0.1.7', build=8):
        return dict(version=version,build=build,url=f'{feed.REPOSITORY}/releases/download/v{version}/Dante-Live-{version}-macOS-universal.dmg',length=123,sha256='a'*64,signature=base64.b64encode(b'a'*64).decode(),minimumSystemVersion='14.0',architectures=['arm64','x86_64'],publishedAt='2026-10-15T18:00:00+00:00',changelog='## Novidades\nTexto <seguro> & mudança')
    def test_order_and_escape(self):
        tree=ET.fromstring(feed.appcast([self.record(),self.record('0.1.8',9)]))
        self.assertEqual(tree.find('channel/item/{'+feed.SPARKLE+'}version').text,'9')
        self.assertEqual(tree.find('channel/item/description').text,self.record()['changelog'])
    def test_reject_unsafe_or_incomplete_records(self):
        for key,value in [('url','https://evil.example/app.dmg'),('build',0),('signature','bad'),('sha256','bad'),('length',0),('minimumSystemVersion','13.0'),('architectures',['arm64']),('changelog','')]:
            record=self.record();record[key]=value
            with self.assertRaises((ValueError,TypeError)):feed.appcast([record])
    def test_duplicates_and_empty_feed(self):
        with self.assertRaises(ValueError):feed.appcast([self.record(),self.record()])
        self.assertEqual(len(ET.fromstring(feed.appcast([])).findall('channel/item')),0)
if __name__=='__main__':unittest.main()
