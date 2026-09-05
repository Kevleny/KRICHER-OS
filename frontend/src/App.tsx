import { useCallback, useEffect, useRef, useState } from 'react'
import { Activity, ArrowUpRight, Bell, Bot, Box, CalendarClock, Check, ChevronRight, Cpu, Database, HardDrive, Home, KeyRound, LayoutDashboard, Mail, Power, RefreshCw, RotateCcw, Send, Server, Settings, ShieldCheck, Workflow, X } from 'lucide-react'
import './App.css'

type DriveStatus = { letter: string; label: string; totalGb: number; freeGb: number; usedPercent: number }
type HostStatus = { checkedAt: string; uptimeSeconds: number; cpuLoadPercent: number; memory: { totalGb: number; usedGb: number; usedPercent: number }; drives: DriveStatus[]; backup: { createdAt: string; ageHours: number } | null; docker: { startsWithSession: boolean } }
type WatchedService = { healthy: boolean; state: string; consecutiveFailures: number; lastRepairAt: string | null }
type WatchdogStatus = { checkedAt: string; mode: string; healthy: boolean; dockerAvailable: boolean; services: Record<string, WatchedService>; repairs: { service: string; attemptedAt: string; succeeded: boolean }[]; restartScheduled: boolean; interventionRequired: boolean }
type BackupStatus = { state: 'running' | 'success' | 'failed'; message: string; checkedAt: string; completedAt?: string; retentionDays: number; monthlyRetention: number; encrypted: boolean; totalBytes?: number }
type BackupVerificationStatus = { state: 'running' | 'success' | 'failed'; message: string; checkedAt: string; completedAt?: string }
type NotificationStatus = { configured: boolean; checkedAt: string; recipient?: string; weeklySchedule?: string; lastSentAt?: string; lastWeeklyAt?: string; lastError?: string; message: string }
type Status = { version: string; startedAt: string; uptime: number; memoryMb: number; node: string; platform: string; checkedAt: string; services: Record<string, boolean>; host: HostStatus | null; watchdog: WatchdogStatus | null; backup: BackupStatus | null; backupVerification: BackupVerificationStatus | null; notifications: NotificationStatus | null }
type Service = { name: string; category: string; icon: typeof Workflow; description: string; next: string; statusKey?: string; url?: string }
type ControlAction = { action: 'restart_service' | 'restart_stack' | 'restart_host' | 'backup_now' | 'verify_backup' | 'send_test_email'; target?: string; label: string }
type ChatMessage = { role: 'user' | 'assistant'; content: string; proposal?: { target: string; reason: string } }

const services: Service[] = [
  { name: 'n8n', category: 'Automatisation', icon: Workflow, description: 'Workflows, newsletters et tâches du quotidien.', next: 'Le contrôle de santé du serveur est actif.', statusKey: 'n8n', url: 'https://n8n.kricher.fr/' },
  { name: 'Home Assistant', category: 'Maison', icon: Home, description: 'Équipements connectés et suivi de la maison.', next: 'Déployer Home Assistant et connecter les premiers équipements.' },
  { name: 'Jellyfin', category: 'Médias', icon: Box, description: 'Films, séries et musique au même endroit.', next: 'Préparer le stockage multimédia avant de déployer Jellyfin.' },
  { name: 'Paperless', category: 'Documents', icon: HardDrive, description: 'Classement et recherche dans tes documents.', next: 'Préparer les volumes persistants et la sauvegarde des documents.' },
  { name: 'Immich', category: 'Photos', icon: LayoutDashboard, description: 'Une bibliothèque privée pour tes souvenirs.', next: 'Définir le stockage photo et une sauvegarde indépendante avant installation.' },
  { name: 'PostgreSQL', category: 'Données', icon: Server, description: 'Les données durables de tes automatisations.', next: 'La base est réservée à n8n et n’est pas exposée sur le réseau.', statusKey: 'postgres' },
]
const watchedLabels: Record<string, string> = { dashboard: 'Tableau de bord', gateway: 'Passerelle HTTPS', n8n: 'n8n', 'n8n-runner': 'Moteur n8n', postgres: 'PostgreSQL' }
const tabs = [{ name: 'Vue d’ensemble', icon: LayoutDashboard }, { name: 'Services', icon: Box }, { name: 'Infrastructure', icon: Server }, { name: 'Assistant', icon: Bot }, { name: 'Sécurité & sauvegardes', icon: ShieldCheck }, { name: 'Paramètres', icon: Settings }]
const duration = (s: number) => s < 60 ? `${Math.floor(s)} s` : s < 3600 ? `${Math.floor(s / 60)} min` : `${Math.floor(s / 3600)} h ${Math.floor(s % 3600 / 60)} min`

export default function App() {
  const [page, setPage] = useState('Vue d’ensemble')
  const [status, setStatus] = useState<Status | null>(null)
  const [error, setError] = useState(false)
  const [busy, setBusy] = useState(false)
  const [selected, setSelected] = useState<typeof services[number] | null>(null)
  const [controlToken, setControlToken] = useState('')
  const [pendingAction, setPendingAction] = useState<ControlAction | null>(null)
  const [controlMessage, setControlMessage] = useState('')
  const [controlBusy, setControlBusy] = useState(false)

  const refresh = useCallback(async (signal?: AbortSignal) => {
    setBusy(true)
    try {
      const response = await fetch('/api/status', { signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(5000)]) : AbortSignal.timeout(5000) })
      if (!response.ok) throw new Error('API unavailable')
      const data: Status = await response.json()
      if (!data.checkedAt || !Number.isFinite(data.memoryMb)) throw new Error('Invalid status')
      setStatus(data); setError(false)
    } catch (err) { if (!(err instanceof DOMException && err.name === 'AbortError')) setError(true) }
    finally { setBusy(false) }
  }, [])

  const loadControlToken = useCallback(async () => {
    const response = await fetch('/api/control/capabilities', { signal: AbortSignal.timeout(5000) })
    if (!response.ok) return ''
    const token = (await response.json()).token || ''
    setControlToken(token)
    return token
  }, [])

  useEffect(() => {
    const controller = new AbortController()
    const initial = setTimeout(() => { void refresh(controller.signal); void loadControlToken() }, 0)
    const timer = setInterval(() => void refresh(controller.signal), 15000)
    return () => { controller.abort(); clearTimeout(initial); clearInterval(timer) }
  }, [refresh, loadControlToken])
  useEffect(() => { document.title = `${page} · KRICHER OS` }, [page])

  async function executeAction(action: ControlAction) {
    setPendingAction(null); setControlBusy(true); setControlMessage('Transmission à Windows…')
    try {
      let activeToken = controlToken || await loadControlToken()
      let response = await fetch('/api/control/request', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Kricher-Control-Token': activeToken }, body: JSON.stringify({ action: action.action, target: action.target, confirmation: true }) })
      if (response.status === 403) {
        activeToken = await loadControlToken()
        response = await fetch('/api/control/request', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Kricher-Control-Token': activeToken }, body: JSON.stringify({ action: action.action, target: action.target, confirmation: true }) })
      }
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'Action refusée')
      const id = data.request.id
      if (action.action === 'restart_host') { setControlMessage('Redémarrage de Windows demandé. La page sera momentanément indisponible.'); return }
      for (let attempt = 0; attempt < 50; attempt++) {
        await new Promise(resolve => setTimeout(resolve, 2000))
        try {
          response = await fetch(`/api/control/requests/${id}`, { headers: { 'X-Kricher-Control-Token': activeToken }, signal: AbortSignal.timeout(5000) })
          if (response.status === 403) { activeToken = await loadControlToken(); continue }
          const result = await response.json()
          if (result.state === 'completed') { setControlMessage(result.message); await refresh(); return }
          if (result.state === 'failed') throw new Error(result.message || 'Le redémarrage a échoué')
        } catch (err) {
          if (err instanceof Error && err.message.includes('échoué')) throw err
        }
      }
      setControlMessage('L’action continue en arrière-plan. Actualise l’état dans un instant.')
    } catch (err) { setControlMessage(err instanceof Error ? err.message : 'Action impossible') }
    finally { setControlBusy(false) }
  }

  function proposeTarget(target: string) {
    if (target === 'host') setPendingAction({ action: 'restart_host', label: 'Redémarrer Windows' })
    else if (target === 'stack') setPendingAction({ action: 'restart_stack', label: 'Redémarrer tous les services' })
    else setPendingAction({ action: 'restart_service', target, label: `Redémarrer ${watchedLabels[target] || target}` })
  }

  const online = status !== null && !error
  const host = status?.host
  const backupDrive = host?.drives.find(drive => drive.letter === 'K:')
  return <div className="shell">
    <a className="skip-link" href="#main">Aller au contenu</a>
    <aside className="sidebar">
      <div className="brand"><img src="/kricher-shield.svg" alt=""/><div>KRICHER <b>OS</b><small>SENTINEL HOMELAB</small></div></div>
      <div className="nav-label">ESPACE PERSONNEL</div>
      <nav aria-label="Navigation principale">{tabs.map(({ name, icon: Icon }) => <button key={name} onClick={() => setPage(name)} aria-current={page === name ? 'page' : undefined} className={page === name ? 'active' : ''}><Icon size={19}/>{name}{page === name && <span className="nav-dot"/>}</button>)}</nav>
      <div className="sidebar-bottom"><span className="server-icon"><Server size={20}/></span><div>OptiPlex 3080<small>Serveur personnel · local</small></div></div>
    </aside>
    <div className="workspace"><header className="topbar"><span>Homelab <ChevronRight size={14}/> <strong>{page}</strong></span><span className="local-pill">Accès sécurisé</span></header>
      <main id="main">
        <div className="page-heading"><div><p className="eyebrow">{page === 'Sécurité & sauvegardes' ? 'PROTECTION · REPRISE APRÈS PANNE' : 'TON ESPACE, TES DONNÉES.'}</p><h1>{page === 'Vue d’ensemble' ? 'Bienvenue chez toi.' : page}</h1><p className="muted">{page === 'Vue d’ensemble' ? 'Le point de départ de ton serveur personnel.' : page === 'Sécurité & sauvegardes' ? 'Sauvegardes automatiques, restauration vérifiée et alertes utiles.' : 'KRICHER OS · OptiPlex 3080'}</p></div><button className="button" disabled={busy} onClick={() => void refresh()}><RefreshCw size={16} className={busy ? 'spinning' : ''}/>{busy ? 'Actualisation…' : 'Actualiser'}</button></div>
        {error && <div className="error" role="alert">L’application ne répond pas. Les dernières mesures peuvent être anciennes. <button onClick={() => void refresh()}>Réessayer</button></div>}
        {page === 'Vue d’ensemble' && <SentinelOverview status={status} host={host} backupDrive={backupDrive} busy={controlBusy} message={controlMessage} propose={proposeTarget} openAssistant={() => setPage('Assistant')}/>}
        {page === 'Infrastructure' && <section className="overview" aria-label="État du système">
          <article className="main-status"><div className="status-kicker"><Activity size={18}/> KRICHER OS <span className="badge">{online ? 'En ligne' : error ? 'Indisponible' : 'Connexion…'}</span></div><h2>{online ? 'Le socle est prêt.' : error ? 'Connexion interrompue.' : 'Connexion au serveur…'}</h2><p>Le serveur se surveille et tente de réparer<br/>automatiquement ses services essentiels.</p><div className="status-footer"><span>VERSION {status?.version ?? '0.4.0'}</span><span>LOCAL FIRST <ArrowUpRight size={14}/></span></div></article>
          <article className="metric"><div><Activity size={19}/><span>Disponibilité</span></div><strong>{status ? duration(host?.uptimeSeconds ?? status.uptime) : '—'}</strong><p>Depuis le démarrage du serveur</p><div className="metric-bottom"><span className={online ? 'dot' : 'dot offline'}/>{online ? 'Application accessible' : 'En attente de connexion'}</div></article>
          <article className="metric"><div><Cpu size={19}/><span>Mémoire du serveur</span></div><strong>{host ? Math.round(host.memory.usedPercent) : status ? Math.round(status.memoryMb) : '—'}<small>{host ? ' %' : ' Mo'}</small></strong><p>{host ? `${host.memory.usedGb} Go utilisés sur ${host.memory.totalGb} Go` : 'Processus KRICHER OS uniquement'}</p><div className="metric-bottom">Mesure Windows · toutes les 5 min</div></article>
        </section>}
        {page === 'Services' && <section className="services"><div className="section-heading"><h2>Tes services <span>06</span></h2><span className="muted">Installés progressivement</span></div><div className="service-grid">{services.map((service, index) => { const available = service.statusKey ? status?.services?.[service.statusKey] === true : false; return <button className="service-card" key={service.name} onClick={() => setSelected(service)}><div className="service-top"><span className={`service-icon color-${index}`}><service.icon size={23}/></span><ArrowUpRight size={18}/></div><span className="service-category">{service.category}</span><h3>{service.name}</h3><p>{service.description}</p><span className="service-state"><span className={`dot ${available ? '' : 'offline'}`}/>{available ? 'En ligne' : 'Non configuré'}</span></button> })}</div></section>}
        {page === 'Infrastructure' && <><section className="panel"><h2>OptiPlex 3080</h2><dl><div><dt>Processeur</dt><dd>{host ? `${Math.round(host.cpuLoadPercent)} %` : 'En attente'}</dd></div><div><dt>Mémoire</dt><dd>{host ? `${host.memory.usedGb} / ${host.memory.totalGb} Go` : 'En attente'}</dd></div><div><dt>Disque de sauvegarde K:</dt><dd>{backupDrive ? `${backupDrive.freeGb} Go libres sur ${backupDrive.totalGb} Go` : 'En attente'}</dd></div><div><dt>Dernière sauvegarde</dt><dd>{host?.backup ? `${new Date(host.backup.createdAt).toLocaleString('fr-FR')} · il y a ${Math.round(host.backup.ageHours)} h` : 'Aucune mesure'}</dd></div><div><dt>Démarrage Docker</dt><dd>{host?.docker.startsWithSession ? 'Automatique' : 'À vérifier'}</dd></div><div><dt>Surveillance</dt><dd>{status?.watchdog?.healthy ? 'Tous les services répondent' : status?.watchdog ? 'Réparation ou contrôle en cours' : 'Initialisation'}</dd></div></dl></section><ControlPanel status={status?.watchdog || null} busy={controlBusy} message={controlMessage} propose={setPendingAction}/></>}
        {page === 'Assistant' && <AssistantPage status={status} onProposal={proposeTarget} controlMessage={controlMessage}/>}
        {page === 'Sécurité & sauvegardes' && <SecurityBackupPage status={status} backupDrive={backupDrive} busy={controlBusy} message={controlMessage} propose={setPendingAction}/>}
        {page === 'Paramètres' && <section className="panel"><h2>Une installation personnelle</h2><dl><div><dt>Version</dt><dd>{status?.version ?? '0.4.0'}</dd></div><div><dt>Adresse publique</dt><dd>www.kricher.fr</dd></div><div><dt>Accès distant</dt><dd>HTTPS</dd></div><div><dt>Authentification</dt><dd>Accès protégé</dd></div><div><dt>Assistant</dt><dd>IA en ligne si une clé API est configurée · mode local sinon</dd></div></dl><p className="muted">Les commandes proposées par l’assistant restent limitées à une liste sûre et demandent toujours une confirmation.</p></section>}
        <footer><span><Check size={14}/> Données conservées sur ton serveur</span><span>{status ? `Dernière mesure à ${new Date(status.checkedAt).toLocaleTimeString('fr-FR')}` : 'Connexion en cours'}</span></footer>
      </main>
    </div>
    {selected && <ServiceDialog service={selected} onClose={() => setSelected(null)}/>}
    {pendingAction && <ConfirmDialog action={pendingAction} onCancel={() => setPendingAction(null)} onConfirm={() => void executeAction(pendingAction)}/>}
  </div>
}

function SentinelOverview({ status, host, backupDrive, busy, message, propose, openAssistant }: { status: Status | null; host: HostStatus | null | undefined; backupDrive: DriveStatus | undefined; busy: boolean; message: string; propose: (target: string) => void; openAssistant: () => void }) {
  const watched = status?.watchdog
  const allHealthy = watched?.healthy === true
  const storageUsed = backupDrive ? Math.round(backupDrive.usedPercent) : null
  const metrics = [
    { label: 'Processeur', value: host ? `${Math.round(host.cpuLoadPercent)}%` : '—', detail: 'Charge Windows', icon: Cpu },
    { label: 'Mémoire', value: host ? `${Math.round(host.memory.usedPercent)}%` : '—', detail: host ? `${host.memory.usedGb} / ${host.memory.totalGb} Go` : 'Mesure en attente', icon: Activity },
    { label: 'Sauvegarde K:', value: storageUsed === null ? '—' : `${storageUsed}%`, detail: backupDrive ? `${backupDrive.freeGb} Go libres` : 'Disque en attente', icon: HardDrive },
    { label: 'Dernière sauvegarde', value: host?.backup ? `${Math.round(host.backup.ageHours)} h` : '—', detail: host?.backup ? new Date(host.backup.createdAt).toLocaleDateString('fr-FR') : 'Aucune mesure', icon: ShieldCheck },
    { label: 'Automatisation', value: status?.services.n8n ? 'Active' : 'Arrêtée', detail: 'n8n', icon: Workflow },
  ]
  return <div className="sentinel-dashboard">
    <section className="sentinel-banner">
      <img src="/kricher-shield.svg" alt="Bouclier KRICHER OS"/>
      <div><p className="eyebrow">SENTINEL · CENTRE DE CONTRÔLE</p><h2>{allHealthy ? 'Tous les services sont opérationnels.' : watched ? 'Une intervention est en cours.' : 'Initialisation de la surveillance…'}</h2><p>Surveillance Windows, réparation automatique et commandes protégées.</p></div>
      <span className={`sentinel-state ${allHealthy ? '' : 'warning'}`}><i className={`dot ${allHealthy ? '' : 'offline'}`}/>{allHealthy ? 'Système protégé' : 'À surveiller'}</span>
    </section>

    <section className="sentinel-metrics" aria-label="Mesures principales">{metrics.map(({ label, value, detail, icon: Icon }) => <article key={label}><div><Icon size={16}/><span>{label}</span></div><strong>{value}</strong><small>{detail}</small></article>)}</section>

    <div className="sentinel-columns">
      <section className="sentinel-services"><div className="section-heading"><div><p className="eyebrow">SERVICES SURVEILLÉS</p><h2>État en temps réel</h2></div><span className="watch-frequency">Toutes les 2 min</span></div>
        <div className="sentinel-service-list">{Object.entries(watchedLabels).map(([key, label]) => { const service = watched?.services?.[key]; return <div className="sentinel-service" key={key}><span className="service-badge"><Server size={17}/></span><div><strong>{label}</strong><small>{service?.healthy ? 'Opérationnel' : service ? service.state : 'Mesure en attente'}</small></div><span className={`service-health ${service?.healthy ? '' : 'down'}`}><i className={`dot ${service?.healthy ? '' : 'offline'}`}/>{service?.healthy ? 'En ligne' : 'À vérifier'}</span><button disabled={busy} className="restart-link" onClick={() => propose(key)}><RotateCcw size={14}/> Redémarrer</button></div> })}</div>
        <div className="sentinel-actions"><button disabled={busy} className="button subtle" onClick={() => propose('stack')}><RotateCcw size={15}/> Redémarrer les services</button><button disabled={busy} className="button danger" onClick={() => propose('host')}><Power size={15}/> Redémarrer Windows</button></div>
        {message && <p className="action-message" role="status">{message}</p>}
      </section>

      <aside className="sentinel-assistant"><div className="assistant-orb"><Bot size={25}/></div><p className="eyebrow">ASSISTANT KRICHER OS</p><h2>Ton copilote local.</h2><p>Demande l’état du serveur ou prépare un redémarrage en langage naturel.</p><div className="assistant-preview"><span>« Quel est l’état de tous les services ? »</span><Send size={16}/></div><button className="button assistant-button" onClick={openAssistant}>Ouvrir le chat <ArrowUpRight size={16}/></button><div className="assistant-guard"><ShieldCheck size={15}/> Aucune commande libre · confirmation obligatoire</div></aside>
    </div>
  </div>
}

function SecurityBackupPage({ status, backupDrive, busy, message, propose }: { status: Status | null; backupDrive: DriveStatus | undefined; busy: boolean; message: string; propose: (action: ControlAction) => void }) {
  const backup = status?.backup
  const verification = status?.backupVerification
  const notifications = status?.notifications
  const healthy = status?.watchdog?.healthy === true
  const protectedState = healthy && backup?.state === 'success' && verification?.state === 'success'
  const completed = backup?.completedAt ? new Date(backup.completedAt) : null
  const backupDate = completed ? completed.toDateString() === new Date().toDateString() ? 'Aujourd’hui' : completed.toLocaleDateString('fr-FR') : 'En attente'
  const backupDetail = completed ? `${completed.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })} · validée et chiffrée` : backup?.message || 'aucune donnée'
  const verificationDate = verification?.completedAt ? new Date(verification.completedAt).toLocaleDateString('fr-FR') : 'En attente'
  const items = [
    { name: 'n8n et ses workflows', detail: 'Quotidien · 03:30 · chiffré', icon: Workflow },
    { name: 'Base PostgreSQL', detail: 'Quotidien · intégrité vérifiée', icon: Database },
    { name: 'Configuration et secrets', detail: 'À chaque sauvegarde · chiffré', icon: KeyRound },
    { name: 'Test de restauration', detail: 'Chaque dimanche · sans toucher à la production', icon: ShieldCheck },
  ]
  return <div className="security-dashboard">
    <section className={`security-hero ${protectedState ? '' : 'attention'}`}><span className="security-shield"><ShieldCheck size={34}/></span><div><p className="eyebrow">ÉTAT GÉNÉRAL</p><h2>{protectedState ? 'Ton serveur est protégé et sauvegardé.' : 'La protection est en cours de finalisation.'}</h2><p>{healthy ? 'Les services répondent.' : 'Un service demande une vérification.'} {backup?.message || 'Première sauvegarde en préparation.'}</p></div><span className={`security-health ${protectedState ? '' : 'pending'}`}><i className={`dot ${protectedState ? '' : 'offline'}`}/>{protectedState ? 'Tous les contrôles OK' : 'Configuration en cours'}</span></section>

    <section className="security-metrics" aria-label="État des sauvegardes">
      <article><p>DERNIÈRE SAUVEGARDE</p><strong>{backupDate}</strong><small>{backupDetail}</small></article>
      <article><p>RÉTENTION</p><strong>{backup?.retentionDays ?? 30} jours</strong><small>+ {backup?.monthlyRetention ?? 12} sauvegardes mensuelles</small></article>
      <article><p>ESPACE K:</p><strong>{backupDrive ? `${backupDrive.freeGb} Go` : '—'}</strong><small>disponibles</small></article>
      <article><p>TEST DE RESTAURATION</p><strong>{verification?.state === 'success' ? 'Réussi' : verification?.state === 'failed' ? 'Échec' : 'En attente'}</strong><small>{verificationDate}</small></article>
      <article><p>PROCHAIN RAPPORT</p><strong>Dimanche</strong><small>18:00 · par e-mail</small></article>
    </section>

    <div className="security-columns">
      <section className="security-panel"><p className="eyebrow">SAUVEGARDES AUTOMATIQUES</p><h2>Plan de protection</h2><p className="security-intro">Les données vitales sont copiées sur K: et leur restauration est testée.</p><div className="protection-list">{items.map(({ name, detail, icon: Icon }) => <div className="protection-row" key={name}><span><Icon size={17}/></span><div><strong>{name}</strong><small>{detail}</small></div><em>{verification?.state === 'failed' && name === 'Test de restauration' ? 'À vérifier' : 'Protégé'}</em></div>)}</div><div className="security-actions"><button className="button assistant-button" disabled={busy} onClick={() => propose({ action: 'backup_now', label: 'Lancer une sauvegarde maintenant' })}><HardDrive size={16}/> Sauvegarder maintenant</button><button className="button subtle" disabled={busy || backup?.state !== 'success'} onClick={() => propose({ action: 'verify_backup', label: 'Tester la dernière sauvegarde' })}><ShieldCheck size={16}/> Tester la restauration</button></div></section>

      <section className="security-panel"><p className="eyebrow">NOTIFICATIONS E-MAIL</p><h2>Seulement quand cela compte.</h2><p className="security-intro">Les alertes sont qualifiées et regroupées pour éviter le bruit inutile.</p><div className="mail-rule urgent"><span className="mail-icon"><Bell size={18}/></span><div><p>ALERTE URGENTE · IMMÉDIATE</p><strong>Un service reste arrêté après réparation</strong><small>E-mail après l’échec des tentatives automatiques.</small></div><em>{notifications?.configured ? 'Activée' : 'À configurer'}</em></div><div className="mail-rule weekly"><span className="mail-icon"><CalendarClock size={18}/></span><div><p>RAPPORT HEBDOMADAIRE</p><strong>Résumé complet chaque dimanche à 18:00</strong><small>Services, sauvegardes, stockage, incidents et réparations.</small></div><em>{notifications?.configured ? 'Activé' : 'À configurer'}</em></div><div className="security-actions"><button className="button assistant-button" disabled={busy || !notifications?.configured} onClick={() => propose({ action: 'send_test_email', label: 'Envoyer un e-mail de test' })}><Mail size={16}/> Envoyer un e-mail test</button><span className={`mail-config-state ${notifications?.configured ? 'ready' : ''}`}>{notifications?.configured ? `Destinataire : ${notifications.recipient}` : 'Adresse et compte d’envoi requis'}</span></div></section>
    </div>
    {message && <p className="action-message" role="status">{message}</p>}
  </div>
}

function ControlPanel({ status, busy, message, propose }: { status: WatchdogStatus | null; busy: boolean; message: string; propose: (action: ControlAction) => void }) {
  return <section className="panel control-panel"><div className="section-heading"><div><p className="eyebrow">CONTRÔLE MANUEL</p><h2>Services surveillés</h2></div><span className="muted">Confirmation obligatoire</span></div>
    <div className="control-list">{Object.entries(watchedLabels).map(([key, label]) => { const service = status?.services?.[key]; return <div className="control-row" key={key}><span className={`dot ${service?.healthy ? '' : 'offline'}`}/><div><strong>{label}</strong><small>{service?.healthy ? 'En ligne' : service ? `État : ${service.state}` : 'Mesure en attente'}</small></div><button disabled={busy} className="button subtle" onClick={() => propose({ action: 'restart_service', target: key, label: `Redémarrer ${label}` })}><RotateCcw size={15}/> Redémarrer</button></div> })}</div>
    <div className="control-actions"><button disabled={busy} className="button" onClick={() => propose({ action: 'restart_stack', label: 'Redémarrer tous les services' })}><RotateCcw size={16}/> Tous les services</button><button disabled={busy} className="button danger" onClick={() => propose({ action: 'restart_host', label: 'Redémarrer Windows' })}><Power size={16}/> Windows</button></div>
    {message && <p className="action-message" role="status">{message}</p>}
  </section>
}

function AssistantPage({ status, onProposal, controlMessage }: { status: Status | null; onProposal: (target: string) => void; controlMessage: string }) {
  const [messages, setMessages] = useState<ChatMessage[]>([{ role: 'assistant', content: 'Bonjour. Je peux expliquer l’état de KRICHER OS et préparer un redémarrage sûr. Les actions restent soumises à ta confirmation.' }])
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [mode, setMode] = useState<'local' | 'ai'>('local')
  const bottom = useRef<HTMLDivElement>(null)
  useEffect(() => { bottom.current?.scrollIntoView?.({ behavior: 'smooth' }) }, [messages])
  async function send() {
    const value = text.trim(); if (!value || busy) return
    const next = [...messages, { role: 'user' as const, content: value }]
    setMessages(next); setText(''); setBusy(true)
    try {
      const response = await fetch('/api/assistant', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ messages: next.map(({ role, content }) => ({ role, content })) }) })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'Assistant indisponible')
      setMode(data.mode === 'ai' ? 'ai' : 'local')
      setMessages(current => [...current, { role: 'assistant', content: data.reply, proposal: data.proposal || undefined }])
    } catch { setMessages(current => [...current, { role: 'assistant', content: 'Je ne peux pas répondre pour le moment. Utilise les contrôles de la page Infrastructure.' }]) }
    finally { setBusy(false) }
  }
  return <section className="assistant-layout"><article className="chat-panel"><div className="chat-head"><span><Bot size={22}/></span><div><h2>Assistant KRICHER OS</h2><p>Accès limité à cet environnement</p></div><span className="badge">{status?.watchdog ? mode === 'ai' ? 'IA active' : 'Mode local' : 'Initialisation'}</span></div><div className="chat-messages">{messages.map((message, index) => <div className={`chat-message ${message.role}`} key={index}><p>{message.content}</p>{message.proposal && <button className="button" onClick={() => onProposal(message.proposal!.target)}><Power size={15}/> Examiner et confirmer</button>}</div>)}{busy && <div className="chat-message assistant"><p>Analyse en cours…</p></div>}<div ref={bottom}/></div><form className="chat-input" onSubmit={event => { event.preventDefault(); void send() }}><input value={text} onChange={event => setText(event.target.value)} placeholder="Ex. Quel est l’état du serveur ?" maxLength={1500}/><button aria-label="Envoyer" disabled={busy || !text.trim()}><Send size={18}/></button></form></article><aside className="assistant-help"><h2>Tu peux demander</h2><button onClick={() => setText('Quel est l’état de tous les services ?')}>Quel est l’état des services ?</button><button onClick={() => setText('Redémarre n8n')}>Redémarre n8n</button><button onClick={() => setText('Redémarre tous les services')}>Redémarre tous les services</button><p><ShieldCheck size={17}/> L’assistant prépare l’action. Il ne peut pas lancer de commande arbitraire et attend ta confirmation.</p>{controlMessage && <div className="action-message">{controlMessage}</div>}</aside></section>
}

function ConfirmDialog({ action, onCancel, onConfirm }: { action: ControlAction; onCancel: () => void; onConfirm: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { const dialog = ref.current!; dialog.showModal(); return () => dialog.close() }, [])
  const host = action.action === 'restart_host'
  const descriptions: Record<ControlAction['action'], string> = {
    restart_service: 'Le service sera brièvement indisponible pendant son redémarrage.',
    restart_stack: 'Les services seront brièvement indisponibles pendant leur redémarrage.',
    restart_host: 'Le tableau de bord sera indisponible quelques minutes pendant le redémarrage du serveur.',
    backup_now: 'Une nouvelle copie chiffrée sera créée sur le lecteur K:.',
    verify_backup: 'La sauvegarde sera déchiffrée et testée sans modifier les données en production.',
    send_test_email: 'Un message de contrôle sera envoyé au destinataire configuré.',
  }
  const DialogIcon = action.action === 'backup_now' ? HardDrive : action.action === 'verify_backup' ? ShieldCheck : action.action === 'send_test_email' ? Mail : Power
  return <dialog ref={ref} aria-labelledby="confirm-title" onCancel={onCancel}><div className="dialog-body"><DialogIcon size={32}/><p className="eyebrow">CONFIRMATION REQUISE</p><h2 id="confirm-title">{action.label}</h2><p>{descriptions[action.action]}</p><div className="dialog-buttons"><button className="button subtle" onClick={onCancel}>Annuler</button><button className={`button ${host ? 'danger' : ''}`} onClick={onConfirm}>Confirmer</button></div></div></dialog>
}

function ServiceDialog({ service, onClose }: { service: Service; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { const dialog = ref.current!; dialog.showModal(); return () => dialog.close() }, [])
  return <dialog ref={ref} aria-labelledby="service-title" onCancel={onClose} onClick={event => { if (event.target === event.currentTarget) onClose() }}><div className="dialog-body"><button className="close-button" aria-label="Fermer" onClick={onClose}><X size={20}/></button><service.icon size={32}/><p className="eyebrow">{service.category}</p><h2 id="service-title">{service.name}</h2><p>{service.description}</p><div className="dialog-next"><strong>Prochaine étape</strong><p>{service.next}</p></div>{service.url ? <a className="button" href={service.url} target="_blank" rel="noreferrer">Ouvrir {service.name} <ArrowUpRight size={16}/></a> : <button className="button" onClick={onClose}>Compris</button>}</div></dialog>
}
