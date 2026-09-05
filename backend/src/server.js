import { createApp } from './app.js'
const host = process.env.HOST || '127.0.0.1'
const port = Number(process.env.PORT || 3001)
const server = createApp().listen(port, host, () => console.log(`KRICHER OS listening on http://${host}:${port}`))
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)))
