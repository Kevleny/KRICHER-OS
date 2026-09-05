import test from 'node:test'
import assert from 'node:assert/strict'
import { createApp } from '../src/app.js'

test('health, status and protected control endpoints behave safely', async t => {
  process.env.N8N_HEALTH_URL = 'http://127.0.0.1:1/healthz'
  process.env.POSTGRES_HOST = '127.0.0.1'
  process.env.POSTGRES_PORT = '1'
  const server = createApp({ controlDir: '' }).listen(0, '127.0.0.1')
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
  assert.equal(body.version, '0.4.0')
  assert.equal(body.services.n8n, false)
  assert.equal(body.services.postgres, false)
  assert.ok(body.memoryMb > 0)
  assert.equal(body.host, null)
  assert.equal(body.watchdog, null)
  assert.equal(body.backup, null)
  assert.equal(body.backupVerification, null)
  assert.equal(body.notifications, null)

  const capabilities = await fetch(`${base}/api/control/capabilities`)
  assert.equal(capabilities.status, 200)
  const control = await capabilities.json()
  assert.equal(control.confirmationRequired, true)
  assert.ok(control.services.includes('n8n'))

  const rejected = await fetch(`${base}/api/control/request`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'restart_host', confirmation: true }) })
  assert.equal(rejected.status, 503)

  const assistant = await fetch(`${base}/api/assistant`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ messages: [{ role: 'user', content: 'Redémarre n8n' }] }) })
  assert.equal(assistant.status, 200)
  const answer = await assistant.json()
  assert.equal(answer.proposal.target, 'n8n')
  assert.match(answer.reply, /Confirme/)
})
