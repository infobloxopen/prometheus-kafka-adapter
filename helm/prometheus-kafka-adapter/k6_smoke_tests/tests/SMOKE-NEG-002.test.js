// SMOKE-NEG-002: POST /receive — Invalid protobuf in valid snappy frame
import http from 'k6/http';
import { check, group } from 'k6';
import { isBadRequest } from '../helpers/validators.js';
import { logRequest } from '../helpers/utils.js';
import { getAuthParams } from '../helpers/auth.js';

export function runNEG002(baseUrl) {
  group('SMOKE-NEG-002: Invalid protobuf in snappy frame', () => {
    const url = `${baseUrl}/receive`;
    const params = getAuthParams({ 'Content-Type': 'application/x-protobuf' });
    // Minimal snappy block: single-byte literal "X"
    const snappyGarbage = String.fromCharCode(0x01, 0x00, 0x58);
    const res = http.post(url, snappyGarbage, params);
    logRequest('smoke-neg-002', '/receive', 'POST', url, '[snappy garbage]', res);

    check(res, {
      'invalid protobuf returns 400': isBadRequest,
    });
  });
}
