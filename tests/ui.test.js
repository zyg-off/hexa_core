// node tests/ui.test.js — la page des dialogues dans un vrai navigateur (Chromium) : formulaire, erreurs,
// clavier, liste, date, case à cocher, confirmation, aide. Réponses du jeu simulées.
// Captures : tests/shots/ (si le dossier existe).
const path = require('path'), fs = require('fs');
const { chromium } = require('playwright');
const pageUrl = 'file://' + path.resolve(__dirname, '../web/index.html');
const shots = path.resolve(__dirname, 'shots');
let ok = 0, total = 0;
const check = (name, cond, detail) => { total++; if (cond) ok++; console.log(`${cond ? '✔' : '✘'} ${name}${cond ? '' : ' — ' + JSON.stringify(detail)}`); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const texts = { submit: 'Valider', cancel: 'Annuler', yes: 'Oui', no: 'Non' };

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.addInitScript(() => {
    window.__posts = [];
    window.__reply = { ok: true };
    window.__delay = 0;
    window.HexaDialogPreview = (name, body) => {
      window.__posts.push({ name, body });
      const reply = name === 'submit' ? window.__reply : { ok: true };
      return window.__delay ? new Promise((r) => setTimeout(() => r(reply), window.__delay)) : reply;
    };
  });
  await page.goto(pageUrl);
  await page.evaluate(() => document.body.classList.add('preview'));
  const send = (msg) => page.evaluate((m) => window.HexaDialog.handle(m), msg);
  const posts = () => page.evaluate(() => window.__posts);
  const last = async () => { const p = await posts(); return p[p.length - 1]; };
  const visible = (sel) => page.isVisible(sel);
  const shot = async (name) => { if (fs.existsSync(shots)) await page.screenshot({ path: path.join(shots, name + '.png') }); };
  const reply = (r) => page.evaluate((x) => { window.__reply = x; }, r);

  // Saisie d'un montant ------------------------------------------------------------------------
  await send({ action: 'open', kind: 'form', title: 'Retrait', description: 'Compte courant', texts,
    fields: [{ type: 'amount', label: 'Montant', numeric: true, unit: '$', hint: 'Entre 1 et 5 000 $', default: '100', required: true }] });
  await sleep(250);
  check('Boîte affichée', await visible('#dialog'));
  check('Titre, libellé, indication', (await page.textContent('#dialogTitle')) === 'Retrait' && (await page.textContent('.field-label')) === 'Montant'
    && (await page.textContent('.field-hint')) === 'Entre 1 et 5 000 $');
  check('Champ actif, valeur par défaut sélectionnée', await page.evaluate(() => document.activeElement.id === 'field0' && document.activeElement.selectionEnd === 3));
  check('Clavier numérique, unité', (await page.getAttribute('#field0', 'inputmode')) === 'decimal' && (await page.textContent('.field-unit')) === '$');
  await page.keyboard.type('9000');
  await reply({ ok: false, errors: [{ index: 1, error: 'Maximum : 5 000.' }] });
  await page.keyboard.press('Enter');
  await sleep(50);
  let p = await last();
  check('Entrée envoie les valeurs brutes', p.name === 'submit' && p.body.values.length === 1 && p.body.values[0] === '9000', p);
  check('Erreur sous le champ', (await page.textContent('.field-error')) === 'Maximum : 5 000.' && await page.evaluate(() => document.querySelector('.field').classList.contains('invalid')));
  await shot('saisie_erreur');
  await page.keyboard.press('Backspace');
  check('L’erreur disparaît dès qu’on corrige', (await page.textContent('.field-error')) === '');
  await reply({ ok: true });
  await page.click('#submitBtn');
  await sleep(50);
  check('Bouton Valider', (await last()).body.values[0] === '900' && !(await visible('#backdrop')));

  // Formulaire complet -------------------------------------------------------------------------
  await send({ action: 'open', kind: 'form', title: 'Amende', description: 'Contravention remise en main propre.', texts, fields: [
    { type: 'select', label: 'Motif', options: ['Excès de vitesse', 'Stationnement gênant', 'Feu rouge'], default: 0, placeholder: 'Choisir…', required: true },
    { type: 'amount', label: 'Montant', numeric: true, unit: '$', hint: 'Entre 50 et 5 000 $', required: true },
    { type: 'date', label: 'Date de l’infraction', default: '06/11/2026', placeholder: 'JJ/MM/AAAA', hint: 'Entre 01/01/2026 et 31/12/2026', required: true },
    { type: 'text', label: 'Remarque', multiline: true, required: false, placeholder: 'Facultatif', hint: '%s / %s caractères', maxLength: 200 },
    { type: 'checkbox', label: 'Envoyer une copie au contrevenant', default: true },
  ] });
  await sleep(250);
  check('5 champs', (await page.$$('.field')).length === 5);
  check('Liste : rien choisi au départ, style indication', (await page.inputValue('#field0')) === '0' && await page.evaluate(() => document.getElementById('field0').classList.contains('placeholder')));
  check('Date : valeur et indication', (await page.inputValue('#field2')) === '06/11/2026' && (await page.getAttribute('#field2', 'placeholder')) === 'JJ/MM/AAAA');
  check('Case cochée par défaut', await page.isChecked('#field4'));
  await shot('formulaire');
  await reply({ ok: false, errors: [{ index: 1, error: 'Ce champ est obligatoire.' }, { index: 2, error: 'Ce champ est obligatoire.' }] });
  await page.click('#submitBtn');
  await sleep(50);
  p = await last();
  check('Valeurs envoyées par type (liste = numéro, case = oui/non)', JSON.stringify(p.body.values) === JSON.stringify([0, '', '06/11/2026', '', true]), p.body.values);
  check('Plusieurs erreurs affichées', (await page.$$('.field.invalid')).length === 2);
  check('Focus sur le premier champ en erreur', await page.evaluate(() => document.activeElement.id === 'field0'));
  await shot('formulaire_erreurs');
  await page.selectOption('#field0', '3');
  check('Choisir efface l’erreur', !(await page.evaluate(() => document.querySelectorAll('.field')[0].classList.contains('invalid'))));
  await page.fill('#field2', '');
  await page.focus('#field2');
  await page.keyboard.type('24122026');
  check('Date tapée : les « / » se placent seuls', (await page.inputValue('#field2')) === '24/12/2026');
  await page.fill('#field1', '135');
  await page.fill('#field3', 'Ligne 1');
  await page.focus('#field3');
  await page.keyboard.press('Enter');
  await page.keyboard.type('Ligne 2');
  check('Zone de texte : Entrée = nouvelle ligne', (await page.inputValue('#field3')) === 'Ligne 1\nLigne 2');
  check('Compteur de caractères', (await page.textContent('.field:nth-child(4) .field-hint')) === '15 / 200 caractères');
  await page.click('.check');
  check('Clic sur le libellé : case décochée', !(await page.isChecked('#field4')));
  await reply({ ok: true });
  await page.keyboard.press('Control+Enter');
  await sleep(50);
  p = await last();
  check('Ctrl + Entrée envoie tout', JSON.stringify(p.body.values) === JSON.stringify([3, '135', '24/12/2026', 'Ligne 1\nLigne 2', false]), p.body.values);

  // Échap, confirmation ------------------------------------------------------------------------
  await send({ action: 'open', kind: 'form', title: 'Plaque', texts, fields: [{ type: 'text', label: 'Plaque', maxLength: 8 }] });
  await sleep(200);
  await page.keyboard.type('HEXA 2026 TROP LONG');
  check('Longueur limitée à la frappe', (await page.inputValue('#field0')) === 'HEXA 202');
  await page.keyboard.press('Escape');
  await sleep(50);
  check('Échap annule', (await last()).name === 'cancel' && !(await visible('#backdrop')));
  await send({ action: 'open', kind: 'confirm', title: 'Vendre le véhicule ?', message: 'Cette action est définitive.', danger: true, submitLabel: 'Vendre', texts });
  await sleep(250);
  check('Confirmation : pas de champ, bouton rouge', (await page.$$('.field')).length === 0 && await page.evaluate(() => document.getElementById('dialog').classList.contains('danger'))
    && (await page.textContent('#submitLabel')) === 'Vendre' && (await page.textContent('#cancelLabel')) === 'Non');
  await shot('confirmation');
  await page.keyboard.press('Escape');
  await sleep(50);
  check('Échap = Non', (await last()).name === 'cancel');
  await send({ action: 'open', kind: 'confirm', title: 'Payer 250 $ ?', texts });
  await sleep(200);
  check('Sans message : ligne masquée', !(await visible('#dialogText')));
  const before = (await posts()).filter((x) => x.name === 'submit').length;
  await page.evaluate(() => { window.__delay = 150; });
  await page.keyboard.press('Enter');
  await page.keyboard.press('Enter');
  await sleep(250);
  await page.evaluate(() => { window.__delay = 0; });
  check('Double appui pendant l’attente : un seul envoi', (await posts()).filter((x) => x.name === 'submit').length === before + 1);

  // Aide à l'écran ---------------------------------------------------------------------------
  await send({ action: 'help', text: 'Appuyez sur [E] pour ouvrir le garage', position: 'left' });
  await sleep(200);
  check('Aide : [E] en touche', (await page.innerHTML('#helpText')) === 'Appuyez sur <kbd>E</kbd> pour ouvrir le garage');
  let box = await page.locator('#help').boundingBox();
  check('À gauche, au milieu', box.x === 24 && Math.abs(box.y + box.height / 2 - 540) <= 1, box);
  await shot('aide');
  await send({ action: 'help', text: '<img src=x onerror=alert(1)> [Entrée]', position: 'bottom', kind: 'error' });
  check('Texte échappé', (await page.$('#helpText img')) === null && (await page.innerHTML('#helpText')).includes('&lt;img'));
  box = await page.locator('#help').boundingBox();
  check('En bas, centrée, couleur d’erreur', Math.abs(box.x + box.width / 2 - 960) <= 1 && await page.evaluate(() => document.getElementById('help').classList.contains('error')));
  await send({ action: 'help' });
  check('Masquée', !(await visible('#help')));

  // Mot de passe, code PIN, curseur, heure ----------------------------------------------------
  await send({ action: 'open', kind: 'form', title: 'Coffre', texts, fields: [
    { type: 'password', label: 'Mot de passe', masked: true, maxLength: 12, required: true },
    { type: 'pin', label: 'Code PIN', masked: true, numeric: true, length: 4, maxLength: 4 },
    { type: 'slider', label: 'Volume', min: 0, max: 100, step: 5, default: 40, unit: '%' },
    { type: 'time', label: 'Heure', placeholder: 'HH:MM', required: true },
  ] });
  await sleep(250);
  check('Mot de passe : champ masqué', (await page.getAttribute('#field0', 'type')) === 'password');
  check('PIN : masqué, clavier numérique', (await page.getAttribute('#field1', 'type')) === 'password' && (await page.getAttribute('#field1', 'inputmode')) === 'numeric');
  await page.focus('#field1');
  await page.keyboard.type('12ab3456');
  check('PIN : chiffres seulement, longueur fixe', (await page.inputValue('#field1')) === '1234');
  check('Curseur : valeur et affichage', (await page.inputValue('#field2')) === '40' && (await page.textContent('.range-value')) === '40 %');
  await page.focus('#field2');
  await page.keyboard.press('ArrowRight');
  check('Curseur : une flèche = un pas', (await page.inputValue('#field2')) === '45' && (await page.textContent('.range-value')) === '45 %');
  await page.focus('#field3');
  await page.keyboard.type('2130');
  check('Heure tapée : le « : » se place seul', (await page.inputValue('#field3')) === '21:30');
  await page.fill('#field0', 'S3cret !');
  await reply({ ok: true });
  await page.click('#submitBtn');
  await sleep(50);
  p = await last();
  check('Envoi : mot de passe brut, PIN, curseur (nombre), heure', JSON.stringify(p.body.values) === JSON.stringify(['S3cret !', '1234', 45, '21:30']), p.body.values);
  await shot('champs_secrets');

  // Menu liste, clavier et manette -----------------------------------------------------------------
  await send({ action: 'open', kind: 'menu', title: 'Garage', texts: { ...texts, empty: 'Aucune option.' }, items: [
    { label: 'Sortir le véhicule' }, { label: 'Réparer', description: '150 $' }, { label: 'Vendre', disabled: true }, { label: 'Fourrière', description: 'Indisponible' } ] });
  await sleep(250);
  check('Menu : 4 options, pas de bouton Valider', (await page.$$('.menu-item')).length === 4 && !(await visible('#submitBtn')) && (await page.textContent('#cancelLabel')) === 'Annuler');
  check('Menu : première option active, description visible', await page.evaluate(() => document.activeElement.textContent.startsWith('Sortir')) && (await page.textContent('.menu-desc')) === '150 $');
  await page.keyboard.press('ArrowDown');
  check('Flèche bas : option suivante', await page.evaluate(() => document.activeElement.textContent.startsWith('Réparer')));
  await page.keyboard.press('ArrowDown');
  check('Option désactivée sautée', await page.evaluate(() => document.activeElement.textContent.startsWith('Fourrière')));
  await send({ action: 'pad', key: 'up' });
  check('Manette : haut', await page.evaluate(() => document.activeElement.textContent.startsWith('Réparer')));
  await page.evaluate(() => { window.__posts.length = 0; });
  await send({ action: 'pad', key: 'accept' });
  await sleep(50);
  p = await last();
  check('Manette A : choisit l’option (numéro 2)', p.name === 'choose' && p.body.index === 2, p);
  await send({ action: 'open', kind: 'menu', title: 'Garage', texts, items: [{ label: 'Sortir' }] });
  await sleep(200);
  await page.keyboard.press('Enter');
  await sleep(50);
  check('Entrée sur une option : la choisit', (await last()).name === 'choose' && (await last()).body.index === 1);
  await send({ action: 'open', kind: 'menu', title: 'Vide', texts: { ...texts, empty: 'Aucune option.' }, items: [] });
  await sleep(200);
  check('Menu vide : message', (await page.textContent('.menu-empty')) === 'Aucune option.');
  await send({ action: 'pad', key: 'cancel' });
  await sleep(50);
  check('Manette B : annule', (await last()).name === 'cancel');

  // Manette dans un formulaire ----------------------------------------------------------------------
  await send({ action: 'open', kind: 'form', title: 'Test', texts, fields: [
    { type: 'select', label: 'Choix', options: ['A', 'B', 'C'], default: 1, placeholder: 'Choisir…', required: true },
    { type: 'checkbox', label: 'Oui' } ] });
  await sleep(250);
  await send({ action: 'pad', key: 'right' });
  check('Manette droite : liste, option suivante', (await page.inputValue('#field0')) === '2');
  await send({ action: 'pad', key: 'down' });
  await send({ action: 'pad', key: 'right' });
  check('Manette droite : case cochée', await page.isChecked('#field1'));
  await send({ action: 'pad', key: 'down' });
  check('Bas : arrive sur Valider', await page.evaluate(() => document.activeElement.id === 'submitBtn'));
  await reply({ ok: true });
  await page.evaluate(() => { window.__posts.length = 0; });
  await send({ action: 'pad', key: 'accept' });
  await sleep(50);
  check('A : valide', (await last()).name === 'submit' && JSON.stringify((await last()).body.values) === JSON.stringify([2, true]), await last());

  // Touches configurables, panneau latéral ----------------------------------------------------------
  await send({ action: 'open', kind: 'form', title: 'Touches', texts, style: 'side', keys: { submit: 'NumpadEnter', cancel: 'End' },
    fields: [{ type: 'text', label: 'Nom', required: false }] });
  await sleep(250);
  check('Touches affichées sur les boutons', (await page.textContent('#submitKey')) === 'Entrée (pavé)' && (await page.textContent('#cancelKey')) === 'End');
  box = await page.locator('#dialog').boundingBox();
  check('Panneau latéral : collé à droite, pleine hauteur', box.x + box.width === 1920 && box.height === 1080 && box.width <= 380, box);
  await shot('panneau_lateral');
  await page.evaluate(() => { window.__posts.length = 0; });
  await page.keyboard.press('Enter');
  await sleep(50);
  check('Entrée normale ne valide plus', (await posts()).length === 0);
  await page.keyboard.press('End');
  await sleep(50);
  check('Touche d’annulation choisie', (await last()).name === 'cancel');
  await send({ action: 'open', kind: 'form', title: 'Normal', texts, style: 'center', fields: [{ type: 'text', label: 'Nom' }] });
  await sleep(200);
  box = await page.locator('#dialog').boundingBox();
  check('Style centré : au milieu de l’écran', Math.abs(box.x + box.width / 2 - 960) <= 1 && Math.abs(box.y + box.height / 2 - 540) <= 2, box);
  await page.keyboard.press('Escape');
  await sleep(50);

  // Écran étroit, long formulaire ----------------------------------------------------------------
  await page.setViewportSize({ width: 360, height: 640 });
  const many = Array.from({ length: 12 }, (_, i) => ({ type: 'text', label: `Champ ${i + 1}` }));
  await send({ action: 'open', kind: 'form', title: 'Long', texts, fields: many });
  await sleep(200);
  box = await page.locator('#dialog').boundingBox();
  check('Écran étroit : la boîte tient dans l’écran', box.x >= 0 && box.x + box.width <= 360 && box.y >= 0 && box.y + box.height <= 640, box);
  check('Formulaire long : défilement interne', await page.evaluate(() => { const f = document.getElementById('fields'); return f.scrollHeight > f.clientHeight; }));

  check('Aucune erreur JavaScript', errors.length === 0, errors);
  console.log(`UI : ${ok}/${total}`);
  await browser.close();
  process.exit(ok === total ? 0 : 1);
})();
