import { readFile } from 'node:fs/promises'

const targets = ['dashboard', 'gateway', 'n8n', 'n8n-runner', 'postgres', 'stack', 'host']
const labels = { dashboard: 'le tableau de bord', gateway: 'la passerelle HTTPS', n8n: 'n8n', 'n8n-runner': 'le moteur n8n', postgres: 'PostgreSQL', stack: 'tous les services', host: 'le serveur Windows' }

async function readApiKey() {
  if (process.env.OPENAI_API_KEY) return process.env.OPENAI_API_KEY.trim()
  if (!process.env.OPENAI_API_KEY_FILE) return ''
  try { return (await readFile(process.env.OPENAI_API_KEY_FILE, 'utf8')).trim() } catch { return '' }
}

function findTarget(text) {
  if (/serveur|windows|ordinateur|machine|optiplex/.test(text)) return 'host'
  if (/tous|tout le système|toute la pile|stack/.test(text)) return 'stack'
  if (/runner|moteur n8n/.test(text)) return 'n8n-runner'
  if (/postgres|base de données|bdd/.test(text)) return 'postgres'
  if (/caddy|passerelle|https|gateway/.test(text)) return 'gateway'
  if (/tableau|dashboard|interface/.test(text)) return 'dashboard'
  if (/n8n/.test(text)) return 'n8n'
  return null
}

function statusSummary(status) {
  const states = status.watchdog?.services || {}
  const unavailable = Object.entries(states).filter(([, value]) => value?.healthy !== true).map(([name]) => labels[name] || name)
  if (!unavailable.length && status.services.n8n && status.services.postgres) return 'Tous les services surveillés répondent normalement.'
  return unavailable.length ? `Services à vérifier : ${unavailable.join(', ')}.` : 'Les mesures Windows ne sont pas encore disponibles.'
}

function localAssistant(message, status, note = '') {
  const normalized = message.toLocaleLowerCase('fr-FR')
  const target = findTarget(normalized)
  if (/redémarr|redemarr|restart|relanc/.test(normalized) && target) {
    return { mode: 'local', reply: `${note}Je peux préparer le redémarrage de ${labels[target]}. Confirme l’action ci-dessous pour l’exécuter.`, proposal: { target, reason: 'Demande formulée dans le chat' } }
  }
  if (/état|etat|statut|santé|sante|fonctionn|problème|probleme/.test(normalized)) return { mode: 'local', reply: `${note}${statusSummary(status)}`, proposal: null }
  return { mode: 'local', reply: `${note}Je peux résumer l’état du serveur ou préparer le redémarrage de n8n, PostgreSQL, la passerelle HTTPS, le tableau de bord, tous les services ou Windows. Toute action doit être confirmée.`, proposal: null }
}

export async function askAssistant(messages, status) {
  const lastMessage = messages.at(-1)?.content?.trim() || ''
  if (!lastMessage) return localAssistant('', status)
  const apiKey = await readApiKey()
  if (!apiKey) return localAssistant(lastMessage, status)

  const serviceState = JSON.stringify({ checkedAt: status.checkedAt, services: status.services, watchdog: status.watchdog, host: status.host })
  try {
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(20_000),
      body: JSON.stringify({
        model: process.env.OPENAI_MODEL || 'gpt-5.4-mini',
        store: false,
        max_output_tokens: 500,
        instructions: `Tu es l’assistant privé de KRICHER OS. Réponds en français, brièvement et sans jargon. Voici l’état actuel : ${serviceState}. Tu ne peux jamais exécuter de commande. Quand l’utilisateur demande un redémarrage, appelle uniquement propose_restart; l’interface demandera ensuite une confirmation. N’invente aucun service ni aucune mesure.`,
        input: messages.slice(-10).map(item => ({ role: item.role === 'assistant' ? 'assistant' : 'user', content: String(item.content).slice(0, 1500) })),
        tools: [{ type: 'function', name: 'propose_restart', description: 'Prépare une action de redémarrage autorisée sans l’exécuter.', strict: true, parameters: { type: 'object', properties: { target: { type: 'string', enum: targets }, reason: { type: 'string' } }, required: ['target', 'reason'], additionalProperties: false } }],
        tool_choice: 'auto',
      }),
    })
    if (!response.ok) throw new Error(`OpenAI ${response.status}`)
    const data = await response.json()
    const text = (data.output || []).flatMap(item => item.content || []).filter(item => item.type === 'output_text').map(item => item.text).join('\n').trim()
    const call = (data.output || []).find(item => item.type === 'function_call' && item.name === 'propose_restart')
    let proposal = null
    if (call) {
      const parsed = JSON.parse(call.arguments)
      if (targets.includes(parsed.target)) proposal = { target: parsed.target, reason: String(parsed.reason).slice(0, 300) }
    }
    return { mode: 'ai', reply: text || (proposal ? `Je peux préparer le redémarrage de ${labels[proposal.target]}. Confirme l’action ci-dessous.` : statusSummary(status)), proposal }
  } catch {
    return localAssistant(lastMessage, status, 'L’IA en ligne est momentanément indisponible. ')
  }
}
