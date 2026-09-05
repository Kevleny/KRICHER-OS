import express from 'express'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import net from 'node:net'
import { readFile } from 'node:fs/promises'
import { createControlService } from './control.js'
import { askAssistant } from './assistant.js'

async function checkHttp(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(2000) })
    return response.ok
  } catch { return false }
}

function checkTcp(host, port) {
  return new Promise(resolve => {
    const socket = net.createConnection({ host, port })
    const finish = result => { socket.destroy(); resolve(result) }
    socket.setTimeout(2000)
    socket.once('connect', () => finish(true))
    socket.once('timeout', () => finish(false))
    socket.once('error', () => finish(false))
  })
}

async function readHostStatus(file) {
  if (!file) return null
  try {
    const status = JSON.parse(await readFile(file, 'utf8'))
    return status && typeof status.checkedAt === 'string' ? status : null
  } catch { return null }
}

export function createApp(options = {}) {
  const app = express()
  const control = createControlService(options.controlDir ?? process.env.CONTROL_DIR)
  const startedAt = new Date(Date.now() - process.uptime() * 1000).toISOString()
  app.disable('x-powered-by')
  app.use((_req, res, next) => {
    res.set({ 'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'" })
    next()
  })
  app.use(express.json({ limit: '16kb' }))
  async function getStatus() {
    const [n8n, postgres, host, watchdog, backup, backupVerification, notifications] = await Promise.all([
      checkHttp(process.env.N8N_HEALTH_URL || 'http://n8n:5678/healthz'),
      checkTcp(process.env.POSTGRES_HOST || 'postgres', Number(process.env.POSTGRES_PORT || 5432)),
      readHostStatus(process.env.HOST_STATUS_FILE),
      readHostStatus(process.env.WATCHDOG_STATUS_FILE),
      readHostStatus(process.env.BACKUP_STATUS_FILE || '/app/runtime/backup-status.json'),
      readHostStatus(process.env.BACKUP_VERIFICATION_STATUS_FILE || '/app/runtime/backup-verification-status.json'),
      readHostStatus(process.env.NOTIFICATION_STATUS_FILE || '/app/runtime/notification-status.json'),
    ])
    return { version: '0.4.0', startedAt, uptime: process.uptime(), memoryMb: process.memoryUsage().rss / 1024 / 1024, node: process.version, platform: process.platform, checkedAt: new Date().toISOString(), services: { n8n, postgres }, host, watchdog, backup, backupVerification, notifications }
  }
  app.get('/api/health', (_req, res) => res.set('Cache-Control', 'no-store').json({ status: 'ok' }))
  app.get('/api/status', async (_req, res) => {
    res.set('Cache-Control', 'no-store').json(await getStatus())
  })
  app.get('/api/control/capabilities', (_req, res) => res.set('Cache-Control', 'no-store').json(control.capabilities()))
  app.post('/api/control/request', async (req, res) => {
    try {
      const outcome = await control.enqueue(req, req.body)
      if (outcome.error) return res.status(outcome.status).json({ error: outcome.error })
      res.status(202).json({ request: outcome.request })
    } catch { res.status(503).json({ error: 'Impossible de transmettre la demande à Windows.' }) }
  })
  app.get('/api/control/requests/:id', async (req, res) => {
    const outcome = await control.result(req, req.params.id)
    if (outcome.error) return res.status(outcome.status).json({ error: outcome.error })
    res.set('Cache-Control', 'no-store').json(outcome.result)
  })
  app.post('/api/assistant', async (req, res) => {
    const messages = Array.isArray(req.body?.messages) ? req.body.messages.filter(item => ['user', 'assistant'].includes(item?.role) && typeof item?.content === 'string').slice(-10) : []
    if (!messages.length) return res.status(400).json({ error: 'Message manquant.' })
    res.set('Cache-Control', 'no-store').json(await askAssistant(messages, await getStatus()))
  })
  app.use('/api', (_req, res) => res.status(404).json({ error: 'Not found' }))
  const publicDir = fileURLToPath(new URL('../../public/', import.meta.url))
  app.use(express.static(publicDir))
  app.get('/{*path}', (_req, res) => res.sendFile(path.join(publicDir, 'index.html')))
  return app
}
