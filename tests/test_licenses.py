import unittest
from scripts.collect_licenses import lua_license_text


class LuaLicenseTests(unittest.TestCase):
    def test_extracts_notice_without_page_markup_or_navigation(self):
        html = '''<html><head><style>div {color:red}</style></head><body>
        <h1>Navigation</h1><div>Copyright &copy; Lua.org, PUC-Rio.
        <p>Permission is hereby granted, free of charge, <b>to any person</b>.
        <p>The above copyright notice must be included.
        <p>THE SOFTWARE IS PROVIDED "AS IS".</div><footer>Other links</footer></body></html>'''
        text = lua_license_text(html)
        self.assertIn('Copyright © Lua.org, PUC-Rio.', text)
        self.assertIn('free of charge, to any person', text)
        self.assertIn('THE SOFTWARE IS PROVIDED "AS IS".', text)
        self.assertNotIn('<', text)
        self.assertNotIn('Navigation', text)
        self.assertNotIn('Other links', text)

    def test_rejects_missing_or_incomplete_notice(self):
        for html in ('<p>no notice</p>', '<div>Copyright only</div>'):
            with self.assertRaises(ValueError):
                lua_license_text(html)
