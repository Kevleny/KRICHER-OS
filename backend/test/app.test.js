import test from 'node:test'
import assert from 'node:assert/strict'
import { createApp } from '../src/app.js'

test('health and status endpoints report a live application safely', async t => {
  process.env.N8N_HEALTH_URL = 'http://127.0.0.1:1/healthz'
  process.env.POSTGRES_HOST = '127.0.0.1'
  process.env.POSTGRES_PORT = '1'
  const server = createApp().listen(0, '127.0.0.1')
  t.after(() => server.close())
  await new Promise(resolve => server.once('listening', resolve))
  const address = server.address()
  const base = `http://127.0.0.1:${address.port}`

  const health = await fetch(`${base}/api/health`)
  assert.equal(health.status, 200)
  assert.deepEqual(await health.json(), { status: 'ok' })
  assert.equal(health.headers.get('x-frame-options'), 'DENY')

  const status = await fetch(`${base}/api/status`)
  assert.equal(status.status, 200)
  const body = await status.json()
  assert.equal(body.version, '0.1.0')
  assert.equal(body.services.n8n, false)
  assert.equal(body.services.postgres, false)
  assert.ok(body.memoryMb > 0)
})
