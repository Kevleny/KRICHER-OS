import express from 'express'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import net from 'node:net'

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

export function createApp() {
  const app = express()
  const startedAt = new Date(Date.now() - process.uptime() * 1000).toISOString()
  app.disable('x-powered-by')
  app.use((_req, res, next) => {
    res.set({ 'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'" })
    next()
  })
  app.get('/api/health', (_req, res) => res.set('Cache-Control', 'no-store').json({ status: 'ok' }))
  app.get('/api/status', async (_req, res) => {
    const [n8n, postgres] = await Promise.all([
      checkHttp(process.env.N8N_HEALTH_URL || 'http://n8n:5678/healthz'),
      checkTcp(process.env.POSTGRES_HOST || 'postgres', Number(process.env.POSTGRES_PORT || 5432)),
    ])
    res.set('Cache-Control', 'no-store').json({ version: '0.1.0', startedAt, uptime: process.uptime(), memoryMb: process.memoryUsage().rss / 1024 / 1024, node: process.version, platform: process.platform, checkedAt: new Date().toISOString(), services: { n8n, postgres } })
  })
  app.use('/api', (_req, res) => res.status(404).json({ error: 'Not found' }))
  const publicDir = fileURLToPath(new URL('../../public/', import.meta.url))
  app.use(express.static(publicDir))
  app.get('/{*path}', (_req, res) => res.sendFile(path.join(publicDir, 'index.html')))
  return app
}
