import crypto from 'node:crypto'
import path from 'node:path'
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'

const services = ['dashboard', 'gateway', 'n8n', 'n8n-runner', 'postgres']
const actions = ['restart_service', 'restart_stack', 'restart_host', 'backup_now', 'verify_backup', 'send_test_email']

export function createControlService(controlDir = process.env.CONTROL_DIR || '') {
  const token = crypto.randomBytes(32).toString('base64url')
  const lastRequestByAddress = new Map()

  function capabilities() {
    return { token, actions, services, confirmationRequired: true }
  }

  function isAuthorized(req) {
    const supplied = req.get('x-kricher-control-token') || ''
    const a = Buffer.from(token)
    const b = Buffer.from(supplied)
    return a.length === b.length && crypto.timingSafeEqual(a, b)
  }

  async function enqueue(req, body) {
    if (!controlDir) return { error: 'Le contrôle Windows n’est pas configuré.', status: 503 }
    if (!isAuthorized(req)) return { error: 'Session de contrôle expirée.', status: 403 }
    if (body?.confirmation !== true || !actions.includes(body?.action)) return { error: 'Action ou confirmation invalide.', status: 400 }
    if (body.action === 'restart_service' && !services.includes(body.target)) return { error: 'Service non autorisé.', status: 400 }
    if (body.action !== 'restart_service' && body.target != null) return { error: 'Cette action n’accepte pas de cible.', status: 400 }

    const address = req.ip || 'local'
    const now = Date.now()
    if (now - (lastRequestByAddress.get(address) || 0) < 10_000) return { error: 'Patiente quelques secondes avant une nouvelle action.', status: 429 }
    lastRequestByAddress.set(address, now)

    const request = {
      id: crypto.randomUUID(),
      action: body.action,
      target: body.action === 'restart_service' ? body.target : null,
      requestedAt: new Date().toISOString(),
      source: 'dashboard',
    }
    const requestDir = path.join(controlDir, 'requests')
    await mkdir(requestDir, { recursive: true })
    const temporary = path.join(requestDir, `${request.id}.tmp`)
    await writeFile(temporary, JSON.stringify(request), { encoding: 'utf8', flag: 'wx' })
    await rename(temporary, path.join(requestDir, `${request.id}.json`))
    return { request }
  }

  async function result(req, id) {
    if (!controlDir) return { error: 'Le contrôle Windows n’est pas configuré.', status: 503 }
    if (!isAuthorized(req)) return { error: 'Session de contrôle expirée.', status: 403 }
    if (!/^[0-9a-f-]{36}$/i.test(id)) return { error: 'Identifiant invalide.', status: 400 }
    try {
      return { result: JSON.parse(await readFile(path.join(controlDir, 'results', `${id}.json`), 'utf8')) }
    } catch {
      return { result: { id, state: 'pending' } }
    }
  }

  return { capabilities, enqueue, result, services }
}
