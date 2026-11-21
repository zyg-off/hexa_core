// hexa_core : dialogues et aide à l'écran. Affichage seulement : les réponses sont vérifiées dans core/dialog.lua.
(() => {
    const $ = (id) => document.getElementById(id);
    const inGame = typeof GetParentResourceName === 'function';
    const resource = inGame ? GetParentResourceName() : 'hexa_core';

    const backdrop = $('backdrop'), dialog = $('dialog'), fieldsEl = $('fields');
    const submitBtn = $('submitBtn'), cancelBtn = $('cancelBtn');
    let current = null;     // données de la boîte ouverte
    let controls = [];      // { field, el, input, error, foot, hint }
    let waiting = false;

    async function post(name, body = {}) {
        if (!inGame) return window.HexaDialogPreview ? window.HexaDialogPreview(name, body) : { ok: true };
        try {
            const response = await fetch(`https://${resource}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(body),
            });
            return await response.json();
        } catch (e) {
            return { ok: false };
        }
    }

    const make = (tag, className, text) => {
        const el = document.createElement(tag);
        if (className) el.className = className;
        if (text !== undefined && text !== null) el.textContent = text;
        return el;
    };

    // Champs -------------------------------------------------------------------------------------
    function updateHint(c) {
        let text = c.field.hint || '';
        if (c.field.maxLength && text.includes('%s')) {
            text = text.replace('%s', [...c.input.value].length).replace('%s', c.field.maxLength);
        }
        c.hint.textContent = text;
        c.foot.classList.toggle('empty', !text && !c.error.textContent);
    }

    function setError(c, message) {
        c.error.textContent = message || '';
        c.el.classList.toggle('invalid', Boolean(message));
        updateHint(c);
    }

    function buildField(field, index) {
        const el = make('div', 'field');
        const id = `field${index}`;
        let input;
        if (field.type === 'checkbox') {
            const label = make('label', 'check');
            input = make('input');
            input.type = 'checkbox';
            input.id = id;
            input.checked = Boolean(field.default);
            label.append(input, make('span', 'check-box'), make('span', 'check-label', field.label || ''));
            el.append(label);
            if (field.description) el.append(make('p', 'field-desc check-desc', field.description));
        } else {
            if (field.label) { const l = make('label', 'field-label', field.label); l.htmlFor = id; el.append(l); }
            if (field.description) el.append(make('p', 'field-desc', field.description));
            const box = make('div', 'field-box');
            if (field.type === 'select') {
                input = make('select', 'field-input');
                const first = make('option', '', field.placeholder || '');
                first.value = '0';
                if (field.required) first.disabled = true;
                input.append(first);
                (field.options || []).forEach((label, i) => { const o = make('option', '', label); o.value = String(i + 1); input.append(o); });
                input.value = String(field.default || 0);
                const sync = () => input.classList.toggle('placeholder', input.value === '0');
                input.addEventListener('change', sync);
                sync();
            } else if (field.type === 'slider') {
                input = make('input', 'field-range');
                input.type = 'range';
                input.min = field.min; input.max = field.max; input.step = field.step;
                const shown = make('span', 'range-value');
                const sync = () => { shown.textContent = input.value + (field.unit ? ' ' + field.unit : ''); };
                input.addEventListener('input', sync);
                input.value = field.default;
                sync();
                box.append(shown);
            } else if (field.multiline) {
                input = make('textarea', 'field-input area');
                input.rows = 4;
                input.spellcheck = false;
            } else {
                input = make('input', 'field-input');
                input.type = field.masked && field.type === 'password' ? 'password' : 'text';
                input.autocomplete = 'off';
                input.spellcheck = false;
                if (field.numeric) input.inputMode = 'decimal';
                if (field.type === 'pin') {
                    // Code PIN : chiffres seulement, masqués, une case par chiffre (affichage espacé).
                    input.type = 'password';
                    input.inputMode = 'numeric';
                    input.classList.add('pin');
                    input.addEventListener('input', () => { input.value = input.value.replace(/\D/g, '').slice(0, field.length); });
                }
                if (field.type === 'time') {
                    // Heure tapée chiffre par chiffre : le « : » se place seul.
                    input.inputMode = 'numeric';
                    input.maxLength = 5;
                    input.addEventListener('input', (e) => {
                        if (e.inputType && e.inputType.startsWith('delete')) return;
                        const d = input.value.replace(/\D/g, '').slice(0, 4);
                        input.value = [d.slice(0, 2), d.slice(2)].filter(Boolean).join(':');
                    });
                }
                if (field.type === 'date') {
                    // Date tapée chiffre par chiffre : les « / » se placent seuls (JJ/MM/AAAA ou MM/DD/YYYY).
                    input.inputMode = 'numeric';
                    input.maxLength = 10;
                    input.addEventListener('input', (e) => {
                        if (e.inputType && e.inputType.startsWith('delete')) return;
                        const d = input.value.replace(/\D/g, '').slice(0, 8);
                        input.value = [d.slice(0, 2), d.slice(2, 4), d.slice(4)].filter(Boolean).join('/');
                    });
                }
            }
            if (field.type !== 'select' && field.type !== 'slider') {
                input.value = field.default ?? '';
                if (field.placeholder) input.placeholder = field.placeholder;
                if (field.maxLength) input.maxLength = field.maxLength;
            }
            input.id = id;
            box.append(input);
            if (field.unit) { box.append(make('span', 'field-unit', field.unit)); input.classList.add('with-unit'); }
            el.append(box);
        }
        const foot = make('div', 'field-foot');
        const error = make('span', 'field-error');
        error.setAttribute('role', 'alert');
        const hint = make('span', 'field-hint');
        foot.append(error, hint);
        el.append(foot);
        const c = { field, el, input, error, foot, hint };
        input.addEventListener(field.type === 'checkbox' || field.type === 'select' ? 'change' : 'input', () => setError(c, ''));
        updateHint(c);
        return c;
    }

    const valueOf = (c) => {
        if (c.field.type === 'checkbox') return c.input.checked;
        if (c.field.type === 'select') return Number(c.input.value);
        if (c.field.type === 'slider') return Number(c.input.value);
        return c.input.value;
    };

    // Touches configurables (noms JavaScript) et menu liste ---------------------------------------
    let keys = { submit: 'Enter', cancel: 'Escape' };
    const keyNames = { Enter: 'Entrée', Escape: 'Échap', NumpadEnter: 'Entrée (pavé)', Backspace: 'Retour', ' ': 'Espace' };
    const keyLabel = (key) => keyNames[key] || (String(key).length === 1 ? String(key).toUpperCase() : String(key));
    const menuEl = $('menu');
    const menuItems = () => [...menuEl.querySelectorAll('.menu-item')];

    function buildMenu(items, emptyText) {
        menuEl.replaceChildren();
        if (!current || current.kind !== 'menu') { menuEl.classList.add('hidden'); return; }
        menuEl.classList.remove('hidden');
        if (!items.length) { menuEl.append(make('p', 'menu-empty', emptyText || '')); return; }
        items.forEach((item, i) => {
            const b = make('button', 'menu-item');
            b.type = 'button';
            b.disabled = Boolean(item.disabled);
            b.append(make('span', 'menu-label', item.label));
            if (item.description) b.append(make('span', 'menu-desc', item.description));
            b.addEventListener('click', () => choose(i + 1));
            menuEl.append(b);
        });
    }

    async function choose(index) {
        if (!current || waiting) return;
        waiting = true;
        const result = await post('choose', { index });
        waiting = false;
        if (!inGame && result && result.ok) close();
    }

    // Navigation (flèches du clavier et manette) ----------------------------------------------------
    function focusables() {
        const list = [];
        controls.forEach((c) => list.push(c.input));
        menuItems().forEach((b) => { if (!b.disabled) list.push(b); });
        if (!submitBtn.classList.contains('hidden')) list.push(submitBtn);
        list.push(cancelBtn);
        return list;
    }

    function move(step) {
        const list = focusables();
        if (!list.length) return;
        const at = list.indexOf(document.activeElement);
        const next = list[(at + step + list.length) % list.length];
        next.focus();
    }

    function adjust(step) {
        const el = document.activeElement;
        if (!el) return;
        if (el.type === 'range') { el.value = Number(el.value) + step * Number(el.step || 1); el.dispatchEvent(new Event('input', { bubbles: true })); }
        else if (el.tagName === 'SELECT') { const n = Math.max(0, Math.min(el.options.length - 1, el.selectedIndex + step)); if (!el.options[n].disabled) { el.selectedIndex = n; el.dispatchEvent(new Event('change', { bubbles: true })); } }
        else if (el.type === 'checkbox') { el.checked = step > 0; el.dispatchEvent(new Event('change', { bubbles: true })); }
    }

    function pad(key) {
        if (!current) return;
        if (key === 'up') move(-1);
        else if (key === 'down') move(1);
        else if (key === 'left') adjust(-1);
        else if (key === 'right') adjust(1);
        else if (key === 'cancel') cancel();
        else if (key === 'accept') {
            const el = document.activeElement;
            if (el && el.classList && el.classList.contains('menu-item')) el.click();
            else if (el === cancelBtn) cancel();
            else submit();
        }
    }

    // Boîte ----------------------------------------------------------------------------------------
    function open(data) {
        current = data;
        waiting = false;
        const isForm = data.kind === 'form';
        const isMenu = data.kind === 'menu';
        const texts = data.texts || {};
        keys = { submit: (data.keys && data.keys.submit) || 'Enter', cancel: (data.keys && data.keys.cancel) || 'Escape' };
        $('submitKey').textContent = keyLabel(keys.submit);
        $('cancelKey').textContent = keyLabel(keys.cancel);
        backdrop.classList.toggle('side', data.style === 'side');
        dialog.classList.toggle('is-menu', isMenu);
        dialog.classList.toggle('danger', Boolean(data.danger));
        $('dialogTitle').textContent = data.title || '';
        $('dialogTitle').classList.toggle('hidden', !data.title);
        $('dialogText').textContent = ((isForm || isMenu) ? data.description : data.message) || '';
        $('submitLabel').textContent = data.submitLabel || (isForm ? texts.submit : texts.yes);
        $('cancelLabel').textContent = data.cancelLabel || (isForm || isMenu ? texts.cancel : texts.no);
        submitBtn.classList.toggle('hidden', isMenu);
        submitBtn.disabled = false;
        fieldsEl.replaceChildren();
        controls = isForm ? (data.fields || []).map(buildField) : [];
        controls.forEach((c) => fieldsEl.append(c.el));
        buildMenu(isMenu ? (data.items || []) : [], texts.empty);
        backdrop.classList.remove('hidden');
        requestAnimationFrame(() => {
            if (isMenu) { const first = menuItems().find((b) => !b.disabled); if (first) first.focus(); else cancelBtn.focus(); return; }
            const first = controls[0];
            if (first) { first.input.focus(); if (first.input.select) first.input.select(); }
            else submitBtn.focus();
        });
    }

    function close() {
        current = null;
        controls = [];
        menuEl.replaceChildren();
        backdrop.classList.add('hidden');
    }

    async function submit() {
        if (!current || waiting || current.kind === 'menu') return;
        waiting = true;
        submitBtn.disabled = true;
        const body = current.kind === 'form' ? { values: controls.map(valueOf) } : { value: true };
        const result = await post('submit', body);
        waiting = false;
        submitBtn.disabled = false;
        if (result && Array.isArray(result.errors) && result.errors.length) {
            controls.forEach((c) => setError(c, ''));
            result.errors.forEach((e) => { const c = controls[e.index - 1]; if (c) setError(c, e.error); });
            const first = controls[result.errors[0].index - 1];
            if (first) first.input.focus();
        } else if (!inGame && result && result.ok) {
            close();
        }
    }

    async function cancel() {
        if (!current) return;
        await post('cancel');
        if (!inGame) close();
    }

    dialog.addEventListener('submit', (e) => { e.preventDefault(); submit(); });
    cancelBtn.addEventListener('click', cancel);

    document.addEventListener('keydown', (e) => {
        if (!current) return;
        const field = e.target && ['INPUT', 'TEXTAREA'].includes(e.target.tagName);
        const editing = field && (e.key.length === 1 || e.key === 'Backspace' || e.key === 'Delete');   // une touche d'écriture n'annule jamais
        if (e.key === keys.cancel && !editing) { e.preventDefault(); cancel(); return; }
        const onItem = document.activeElement && document.activeElement.classList.contains('menu-item');
        if (current.kind === 'menu' || onItem) {
            if (e.key === 'ArrowDown') { e.preventDefault(); move(1); return; }
            if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); return; }
        }
        if (e.key !== keys.submit && !(keys.submit === 'Enter' && e.key === 'NumpadEnter')) {
            if ((e.key === 'Enter' || e.key === 'NumpadEnter') && e.target && e.target.tagName === 'INPUT' && e.target.type !== 'checkbox') e.preventDefault();   // pas de validation implicite
            return;
        }
        if (e.target === cancelBtn || onItem) return;           // le bouton ou l'option réagit à Entrée seul
        const inArea = e.target && e.target.tagName === 'TEXTAREA';
        if (inArea && !e.ctrlKey) return;            // nouvelle ligne
        e.preventDefault();
        submit();
    });

    // Aide à l'écran : « [E] » devient une touche --------------------------------------------------------
    const escapeHtml = (text) => String(text ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    function help(data) {
        const el = $('help');
        if (!data.text) { el.classList.add('hidden'); return; }
        $('helpText').innerHTML = escapeHtml(data.text).replace(/\[([^\[\]\n]{1,14})\]/g, '<kbd>$1</kbd>');
        el.className = `help ${['left', 'right', 'bottom'].includes(data.position) ? data.position : 'left'}`;
        if (['success', 'error', 'warning'].includes(data.kind)) el.classList.add(data.kind);
    }

    function handle(data) {
        if (!data || !data.action) return;
        if (data.action === 'open') open(data);
        else if (data.action === 'close') close();
        else if (data.action === 'help') help(data);
        else if (data.action === 'pad') pad(data.key);
    }

    window.addEventListener('message', (e) => handle(e.data));
    window.HexaDialog = { handle };   // aperçu et tests

    // Aperçu dans un navigateur : web/index.html?demo
    if (!inGame && location.search.includes('demo')) {
        document.body.classList.add('preview');
        const texts = { submit: 'Valider', cancel: 'Annuler', yes: 'Oui', no: 'Non' };
        handle({ action: 'help', text: 'Appuyez sur [E] pour ouvrir le garage', position: 'left' });
        handle({ action: 'open', kind: 'form', title: 'Amende', description: 'Contravention remise en main propre.', texts, fields: [
            { type: 'select', label: 'Motif', options: ['Excès de vitesse', 'Stationnement gênant', 'Feu rouge'], default: 0, placeholder: 'Choisir…', required: true },
            { type: 'amount', label: 'Montant', numeric: true, unit: '$', hint: 'Entre 50 et 5 000 $', required: true },
            { type: 'date', label: 'Date de l’infraction', default: '06/11/2026', placeholder: 'JJ/MM/AAAA', hint: 'Entre 01/01/2026 et 31/12/2026', required: true },
            { type: 'text', label: 'Remarque', multiline: true, required: false, placeholder: 'Facultatif' },
            { type: 'checkbox', label: 'Envoyer une copie au contrevenant', default: true },
        ] });
    }
})();
