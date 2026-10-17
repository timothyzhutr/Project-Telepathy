"""Screenshot validation and non-queuing behavior use no model checkpoint."""
import base64
from io import BytesIO
import json
import http.client
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'worker'))
from decision import DecisionService
from server import make_server


def png(width=32, height=24, *, format='PNG'):
    output = BytesIO()
    Image.new('RGB', (width, height), 'white').save(output, format=format)
    return base64.b64encode(output.getvalue()).decode('ascii')


class ScreenLanguageTests(unittest.TestCase):
    def setUp(self):
        self.images = []
        def screen_language(image):
            self.images.append((image.format, image.size, image.mode))
            return dict(language='english', request_ms=23, english_score=.7)
        self.service = DecisionService(SimpleNamespace(screen_language=screen_language))
        self.server = make_server(0, self.service, health=lambda: dict(status='ready',
            engine='Qwen3.5/MLX-VLM', model='mlx-community/Qwen3.5-0.8B-MLX-4bit',
            vision=True, quantization='4bit', weight_bytes=625148416))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://127.0.0.1:' + str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def request(self, body, headers=None):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        request = urllib.request.Request(self.url + '/api/screen-language', data=data, headers=headers or {})
        try:
            with urllib.request.urlopen(request, timeout=2) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as response:
            return response.code, json.load(response)

    def test_png_is_decoded_and_revision_is_returned(self):
        status, result = self.request(dict(revision=17, image=png()))
        self.assertEqual((status, result.get('status'), result.get('revision'), result.get('language')),
                         (200, 'ok', 17, 'english'))
        self.assertEqual(result['english_score'], .7)
        self.assertEqual(self.images, [('PNG', (32, 24), 'RGB')])
        self.assertEqual(self.service.__dict__.keys(), {'ranker', 'lock'})

    def test_rejects_invalid_shapes_types_base64_magic_and_truncated_png(self):
        for body in [None, [], {}, dict(revision=True, image=png()), dict(revision=-1, image=png()),
                     dict(revision=1, image=3), dict(revision=1, image='@@@'),
                     dict(revision=1, image=base64.b64encode(b'not png').decode()),
                     dict(revision=1, image=png(format='JPEG')),
                     dict(revision=1, image=base64.b64encode(b'\x89PNG\r\n\x1a\n').decode()),
                     dict(revision=1, image=base64.b64encode(base64.b64decode(png())[:-12]).decode())]:
            with self.subTest(body=str(body)[:70]):
                self.assertEqual(self.request(body)[0], 400)
        self.assertEqual(self.images, [])

    def test_rejects_excessive_dimensions_or_pixels_before_inference(self):
        for size in [(1537, 1), (1, 1537), (1001, 1000)]:
            with self.subTest(size=size):
                self.assertEqual(self.request(dict(revision=1, image=png(*size)))[0], 400)
        self.assertEqual(self.images, [])

    def test_endpoint_body_limit_is_three_mib_and_origin_is_local(self):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=2)
        connection.request('POST', '/api/screen-language', body=b'',
                           headers={'Content-Length': str(3 * 1024 * 1024 + 1)})
        self.assertEqual(connection.getresponse().status, 413)
        connection.close()
        # Image JSON can exceed the smaller text endpoint limit.
        status, _ = self.request(json.dumps(dict(revision=1, image=png())).encode() + b' ' * 9000)
        self.assertEqual(status, 200)
        self.assertEqual(self.request(dict(revision=1, image=png()), {'Origin': 'https://evil.example'})[0], 403)

    def test_busy_image_request_returns_immediately_without_calling_model(self):
        with self.service.lock:
            status, result = self.request(dict(revision=3, image=png()))
        self.assertEqual((status, result.get('status'), result.get('language')), (200, 'busy', 'uncertain'))
        self.assertEqual(self.images, [])

    def test_missing_or_failed_model_produces_uncertain_hint(self):
        self.service.ranker = None
        status, result = self.request(dict(revision=4, image=png()))
        self.assertEqual((status, result.get('status'), result.get('language')), (200, 'ok', 'uncertain'))
        def fail(image):
            raise RuntimeError('private screenshot contents must not leave the worker')
        self.service.ranker = SimpleNamespace(screen_language=fail)
        status, result = self.request(dict(revision=5, image=png()))
        self.assertEqual((status, result.get('status'), result.get('language')), (200, 'ok', 'uncertain'))
        self.assertNotIn('error', result)

    def test_failed_png_decoder_closes_its_image(self):
        closed = []
        def fail():
            raise OSError('truncated image')
        decoded = SimpleNamespace(format='PNG', size=(32, 24), verify=fail, load=fail, close=lambda: closed.append(True))
        body = dict(revision=1, image=png())
        with patch('PIL.Image.open', return_value=decoded):
            with self.assertRaises(ValueError):
                self.service.screen_language(body)
        self.assertEqual(closed, [True])

    def test_health_identifies_current_vision_engine(self):
        with urllib.request.urlopen(self.url + '/api/health') as response:
            result = json.load(response)
        self.assertEqual(result['version'], '0.2.0')
        self.assertEqual(result['engine'], 'Qwen3.5/MLX-VLM')
        self.assertEqual(result['status'], 'ready')
        self.assertTrue(result['vision'])
        self.assertEqual(result['quantization'], '4bit')
        self.assertEqual(result['weight_bytes'], 625148416)


if __name__ == '__main__':
    unittest.main()
