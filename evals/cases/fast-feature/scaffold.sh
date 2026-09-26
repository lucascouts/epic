#!/usr/bin/env bash
# Scaffold: a small Express app, so the request has code to point at.
set -euo pipefail
git init -q
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src/routes src/views test
cat > package.json <<'JSON'
{ "name": "demo-app", "version": "1.0.0", "private": true,
  "scripts": { "start": "node src/server.js", "test": "node --test test/" },
  "dependencies": { "express": "^4.19.2" } }
JSON
cat > src/server.js <<'JS'
const express = require('express');
const app = express();
app.use(express.urlencoded({ extended: false }));
app.use(require('./routes/profile'));
app.use(require('./routes/auth'));
app.use(require('./routes/settings'));
module.exports = app;
if (require.main === module) app.listen(3000);
JS
cat > src/routes/profile.js <<'JS'
const router = require('express').Router();
const users = new Map();
router.get('/profile', (req, res) => res.sendFile(require('path').join(__dirname, '../views/profile.html')));
router.post('/profile', (req, res) => { users.set('me', { name: req.body.name, email: req.body.email }); res.redirect('/profile'); });
module.exports = router;
JS
cat > src/views/profile.html <<'HTML'
<form method="post" action="/profile">
  <input name="name" placeholder="Name">
  <input name="email" placeholder="Email">
  <button type="submit">Save</button>
</form>
HTML
cat > src/routes/auth.js <<'JS'
const router = require('express').Router();
router.post('/login', (req, res) => {
  if (req.body.user === 'demo' && req.body.password === 'demo') { res.status(200).send(''); return; }
  res.status(401).send('invalid');
});
module.exports = router;
JS
cat > src/routes/settings.js <<'JS'
const router = require('express').Router();
router.get('/settings', (req, res) => res.send('<h1>Settings</h1>'));
module.exports = router;
JS
cat > test/profile.test.js <<'JS'
const test = require('node:test');
test('placeholder', () => {});
JS
git add -A && git commit -qm "initial app"
