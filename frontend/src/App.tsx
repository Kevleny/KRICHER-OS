import { useCallback, useEffect, useRef, useState } from 'react'
import { Activity, ArrowUpRight, Box, Check, ChevronRight, Cpu, HardDrive, Home, LayoutDashboard, RefreshCw, Server, Settings, Workflow, X } from 'lucide-react'
import './App.css'

type Status = { version: string; startedAt: string; uptime: number; memoryMb: number; node: string; platform: string; checkedAt: string; services: Record<string, boolean> }
type Service = { name: string; category: string; icon: typeof Workflow; description: string; next: string; statusKey?: string; url?: string }
const services: Service[] = [
  { name: 'n8n', category: 'Automatisation', icon: Workflow, description: 'Workflows, newsletters et tâches du quotidien.', next: 'Construire et tester le premier workflow.', statusKey: 'n8n', url: 'https://n8n.kricher.fr/' },
  { name: 'Home Assistant', category: 'Maison', icon: Home, description: 'Équipements connectés et suivi de la maison.', next: 'Déployer Home Assistant et connecter les premiers équipements.' },
  { name: 'Jellyfin', category: 'Médias', icon: Box, description: 'Films, séries et musique au même endroit.', next: 'Préparer le stockage multimédia avant de déployer Jellyfin.' },
  { name: 'Paperless', category: 'Documents', icon: HardDrive, description: 'Classement et recherche dans tes documents.', next: 'Préparer les volumes persistants et la sauvegarde des documents.' },
  { name: 'Immich', category: 'Photos', icon: LayoutDashboard, description: 'Une bibliothèque privée pour tes souvenirs.', next: 'Définir le stockage photo et une sauvegarde indépendante avant installation.' },
  { name: 'PostgreSQL', category: 'Données', icon: Server, description: 'Les données durables de tes automatisations.', next: 'La base est réservée à n8n et n’est pas exposée sur le réseau.', statusKey: 'postgres' },
]
const tabs = [{ name: 'Vue d’ensemble', icon: LayoutDashboard }, { name: 'Services', icon: Box }, { name: 'Infrastructure', icon: Server }, { name: 'Paramètres', icon: Settings }]
const duration = (s: number) => s < 60 ? `${Math.floor(s)} s` : s < 3600 ? `${Math.floor(s / 60)} min` : `${Math.floor(s / 3600)} h ${Math.floor(s % 3600 / 60)} min`

export default function App() {
  const [page, setPage] = useState('Vue d’ensemble')
  const [status, setStatus] = useState<Status | null>(null)
  const [error, setError] = useState(false)
  const [busy, setBusy] = useState(false)
  const [selected, setSelected] = useState<typeof services[number] | null>(null)
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
  useEffect(() => {
    const controller = new AbortController()
    const initial = setTimeout(() => void refresh(controller.signal), 0)
    const timer = setInterval(() => void refresh(controller.signal), 15000)
    return () => { controller.abort(); clearTimeout(initial); clearInterval(timer) }
  }, [refresh])
  useEffect(() => { document.title = `${page} · KRICHER OS` }, [page])
  const online = status !== null && !error
  return <div className="shell">
    <a className="skip-link" href="#main">Aller au contenu</a>
    <aside className="sidebar">
      <div className="brand"><span className="brand-mark">K<span>.</span></span><div>KRICHER <b>OS</b><small>PERSONAL HOMELAB</small></div></div>
      <div className="nav-label">ESPACE PERSONNEL</div>
      <nav aria-label="Navigation principale">{tabs.map(({ name, icon: Icon }) => <button key={name} onClick={() => setPage(name)} aria-current={page === name ? 'page' : undefined} className={page === name ? 'active' : ''}><Icon size={19}/>{name}{page === name && <span className="nav-dot"/>}</button>)}</nav>
      <div className="sidebar-bottom"><span className="server-icon"><Server size={20}/></span><div>OptiPlex 3080<small>Serveur personnel · local</small></div></div>
    </aside>
    <div className="workspace"><header className="topbar"><span>Homelab <ChevronRight size={14}/> <strong>{page}</strong></span><span className="local-pill">Accès sécurisé</span></header>
      <main id="main">
        <div className="page-heading"><div><p className="eyebrow">TON ESPACE, TES DONNÉES.</p><h1>{page === 'Vue d’ensemble' ? 'Bienvenue chez toi.' : page}</h1><p className="muted">{page === 'Vue d’ensemble' ? 'Le point de départ de ton serveur personnel.' : 'KRICHER OS · OptiPlex 3080'}</p></div><button className="button" disabled={busy} onClick={() => void refresh()}><RefreshCw size={16} className={busy ? 'spinning' : ''}/>{busy ? 'Actualisation…' : 'Actualiser'}</button></div>
        {error && <div className="error" role="alert">L’application ne répond pas. Les dernières mesures peuvent être anciennes. <button onClick={() => void refresh()}>Réessayer</button></div>}
        {(page === 'Vue d’ensemble' || page === 'Infrastructure') && <section className="overview" aria-label="État du système">
          <article className="main-status"><div className="status-kicker"><Activity size={18}/> KRICHER OS <span className="badge">{online ? 'En ligne' : error ? 'Indisponible' : 'Connexion…'}</span></div><h2>{online ? 'Le socle est prêt.' : error ? 'Connexion interrompue.' : 'Connexion au serveur…'}</h2><p>Ton tableau de bord fonctionne sur ce serveur.<br/>Les services viendront le compléter, étape par étape.</p><div className="status-footer"><span>VERSION {status?.version ?? '0.1.0'}</span><span>LOCAL FIRST <ArrowUpRight size={14}/></span></div></article>
          <article className="metric"><div><Activity size={19}/><span>Disponibilité</span></div><strong>{status ? duration(status.uptime) : '—'}</strong><p>Depuis le démarrage de l’application</p><div className="metric-bottom"><span className={online ? 'dot' : 'dot offline'}/>{online ? 'Application accessible' : 'En attente de connexion'}</div></article>
          <article className="metric"><div><Cpu size={19}/><span>Mémoire de l’application</span></div><strong>{status ? Math.round(status.memoryMb) : '—'}<small> Mo</small></strong><p>Processus KRICHER OS uniquement</p><div className="metric-bottom">Mesure en direct · toutes les 15 s</div></article>
        </section>}
        {(page === 'Vue d’ensemble' || page === 'Services') && <section className="services"><div className="section-heading"><h2>Tes services <span>06</span></h2><span className="muted">Installés progressivement</span></div><div className="service-grid">{services.map((service, index) => { const available = service.statusKey ? status?.services?.[service.statusKey] === true : false; return <button className="service-card" key={service.name} onClick={() => setSelected(service)}><div className="service-top"><span className={`service-icon color-${index}`}><service.icon size={23}/></span><ArrowUpRight size={18}/></div><span className="service-category">{service.category}</span><h3>{service.name}</h3><p>{service.description}</p><span className="service-state"><span className={`dot ${available ? '' : 'offline'}`}/>{available ? 'En ligne' : 'Non configuré'}</span></button> })}</div></section>}
        {page === 'Infrastructure' && <section className="panel"><h2>Environnement de l’application</h2><dl><div><dt>Moteur</dt><dd>Node.js {status?.node ?? '—'}</dd></div><div><dt>Plateforme d’exécution</dt><dd>{status?.platform ?? '—'}</dd></div><div><dt>Démarrage</dt><dd>{status ? new Date(status.startedAt).toLocaleString('fr-FR') : '—'}</dd></div><div><dt>Supervision de Windows</dt><dd>Pas encore connectée</dd></div></dl><p className="muted">Ces mesures concernent l’application. Le suivi du processeur, des disques et de la mémoire de l’OptiPlex sera connecté séparément.</p></section>}
        {page === 'Paramètres' && <section className="panel"><h2>Une installation personnelle</h2><dl><div><dt>Version</dt><dd>{status?.version ?? '0.1.0'}</dd></div><div><dt>Adresse publique</dt><dd>www.kricher.fr</dd></div><div><dt>Accès distant</dt><dd>HTTPS</dd></div><div><dt>Authentification</dt><dd>Accès protégé</dd></div></dl><p className="muted">Le tableau de bord et ses services restent hébergés sur ton OptiPlex.</p></section>}
        {page === 'Vue d’ensemble' && <section className="next-step"><div className="step-number">01</div><div><span className="eyebrow">LA SUITE DU HOMELAB</span><h2>Place aux automatisations.</h2><p>n8n et PostgreSQL sont prêts. La prochaine étape est de créer le premier workflow.</p></div><button className="button" onClick={() => setSelected(services[0])}>Voir la prochaine étape <ChevronRight size={16}/></button></section>}
        <footer><span><Check size={14}/> Données conservées sur ton serveur</span><span>{status ? `Dernière mesure à ${new Date(status.checkedAt).toLocaleTimeString('fr-FR')}` : 'Connexion en cours'}</span></footer>
      </main>
    </div>
    {selected && <ServiceDialog service={selected} onClose={() => setSelected(null)}/>}
  </div>
}

function ServiceDialog({ service, onClose }: { service: Service; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { const dialog = ref.current!; dialog.showModal(); return () => dialog.close() }, [])
  return <dialog ref={ref} aria-labelledby="service-title" onCancel={onClose} onClick={event => { if (event.target === event.currentTarget) onClose() }}><div className="dialog-body"><button className="close-button" aria-label="Fermer" onClick={onClose}><X size={20}/></button><service.icon size={32}/><p className="eyebrow">{service.category}</p><h2 id="service-title">{service.name}</h2><p>{service.description}</p><div className="dialog-next"><strong>Prochaine étape</strong><p>{service.next}</p></div>{service.url ? <a className="button" href={service.url} target="_blank" rel="noreferrer">Ouvrir {service.name} <ArrowUpRight size={16}/></a> : <button className="button" onClick={onClose}>Compris</button>}</div></dialog>
}
