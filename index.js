// Clay Tags bot: Discord slash commands + the HTTP endpoint the Clay Client script talks to.
require('dotenv').config();
const fs = require('fs');
const crypto = require('crypto');
const express = require('express');
const {
	Client, GatewayIntentBits, REST, Routes, SlashCommandBuilder,
	PermissionFlagsBits, EmbedBuilder,
} = require('discord.js');

const { DISCORD_TOKEN, CLIENT_ID, GUILD_ID, TAG_KEY } = process.env;
const PORT = process.env.PORT || 3000;
const DATA_FILE = process.env.DATA_FILE || './data.json';
const ADMIN_IDS = (process.env.ADMIN_IDS || '').split(',').map((s) => s.trim()).filter(Boolean);

if (!DISCORD_TOKEN || !CLIENT_ID || !TAG_KEY) {
	console.error('Missing DISCORD_TOKEN, CLIENT_ID or TAG_KEY in the environment.');
	process.exit(1);
}

const USERNAME_RE = /^[A-Za-z0-9_]{3,20}$/;
const ONLINE_TTL = 20_000; // the script beats every 5s, so 20s of silence = gone
const OWNER_COLOR = '#FFCD50';
const COLORS = {
	gold: '#FFCD50', red: '#FF5A5A', orange: '#FF9A3C', yellow: '#FFE24A', green: '#4ADE80',
	cyan: '#3CE0F0', blue: '#4A7BFF', purple: '#A855F7', pink: '#FF66CC', white: '#FFFFFF',
	salmon: '#FA8072',
};

// ---------- storage ----------
let data = { tags: {} };
try {
	data = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
	if (!data.tags) data.tags = {};
} catch { /* first run */ }

function save() {
	const tmp = DATA_FILE + '.tmp';
	fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
	fs.renameSync(tmp, DATA_FILE);
}

// ---------- presence (who is running the script right now) ----------
const online = new Map(); // lowercase username -> { name, job, seen }

function prune() {
	const now = Date.now();
	for (const [k, v] of online) if (now - v.seen > ONLINE_TTL) online.delete(k);
}

// ---------- HTTP ----------
const app = express();
app.set('trust proxy', 1);
app.use(express.json({ limit: '2kb' }));

const hits = new Map();
function rateLimited(ip) {
	const now = Date.now();
	const arr = (hits.get(ip) || []).filter((t) => now - t < 10_000);
	arr.push(now);
	hits.set(ip, arr);
	return arr.length > 30;
}
setInterval(() => hits.clear(), 60_000).unref();

function keyOk(given) {
	const a = Buffer.from(String(given));
	const b = Buffer.from(TAG_KEY);
	return a.length === b.length && crypto.timingSafeEqual(a, b);
}

app.get('/health', (_req, res) => {
	prune();
	res.json({ ok: true, online: online.size });
});

app.post('/beat', (req, res) => {
	if (rateLimited(req.ip)) return res.status(429).json({ error: 'slow down' });
	const b = req.body || {};
	if (!keyOk(b.key ?? '')) return res.status(401).json({ error: 'bad key' });

	const user = String(b.user || '');
	if (!USERNAME_RE.test(user)) return res.status(400).json({ error: 'bad user' });
	const job = String(b.job || '').slice(0, 64);
	const lower = user.toLowerCase();

	if (b.leave === true) {
		online.delete(lower);
		return res.json({ users: [], roles: {} });
	}

	online.set(lower, { name: user, job, seen: Date.now() });
	prune();

	// only hand back people in the same Roblox server as the caller
	const users = [];
	const roles = {};
	for (const [k, v] of online) {
		if (v.job !== job) continue;
		users.push(v.name);
		const t = data.tags[k];
		if (t) roles[k] = { text: t.text, color: t.color, crown: t.crown === true };
	}
	res.json({ users, roles });
});

app.listen(PORT, () => console.log(`Tag server listening on :${PORT}`));

// ---------- Discord ----------
const userOpt = (o) => o.setName('username').setDescription('Roblox username').setRequired(true);

const command = new SlashCommandBuilder()
	.setName('clay')
	.setDescription('Manage Clay Client tags')
	.setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
	.addSubcommand((s) => s.setName('owner')
		.setDescription('Make this account the OWNER (gold name + crown). Only one owner at a time.')
		.addStringOption(userOpt))
	.addSubcommand((s) => s.setName('tag')
		.setDescription('Give an account a custom tag')
		.addStringOption(userOpt)
		.addStringOption((o) => o.setName('text').setDescription('What the tag says (max 20 chars)').setRequired(true))
		.addStringOption((o) => o.setName('color').setDescription('Hex like #ff66cc, or: ' + Object.keys(COLORS).join(', ')))
		.addBooleanOption((o) => o.setName('crown').setDescription('Put a crown on their head too')))
	.addSubcommand((s) => s.setName('remove')
		.setDescription('Remove an account\'s custom tag / owner status')
		.addStringOption(userOpt))
	.addSubcommand((s) => s.setName('list').setDescription('Show every custom tag'))
	.addSubcommand((s) => s.setName('online').setDescription('Show who is running Clay Client right now'));

function parseColor(input) {
	if (!input) return '#FFFFFF';
	const s = input.trim().toLowerCase();
	if (COLORS[s]) return COLORS[s];
	const m = s.match(/^#?([0-9a-f]{6})$/);
	return m ? '#' + m[1].toUpperCase() : null;
}

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

client.once('ready', async () => {
	const rest = new REST({ version: '10' }).setToken(DISCORD_TOKEN);
	const body = [command.toJSON()];
	try {
		if (GUILD_ID) await rest.put(Routes.applicationGuildCommands(CLIENT_ID, GUILD_ID), { body });
		else await rest.put(Routes.applicationCommands(CLIENT_ID), { body });
		console.log(`Logged in as ${client.user.tag}, commands registered.`);
	} catch (e) {
		console.error('Command registration failed:', e);
	}
});

function allowed(i) {
	if (ADMIN_IDS.length) return ADMIN_IDS.includes(i.user.id);
	return i.memberPermissions?.has(PermissionFlagsBits.ManageGuild) === true;
}

client.on('interactionCreate', async (i) => {
	if (!i.isChatInputCommand() || i.commandName !== 'clay') return;
	const reply = (content) => i.reply({ content, ephemeral: true });
	if (!allowed(i)) return reply('You are not allowed to manage tags.');

	const sub = i.options.getSubcommand();

	if (sub === 'list') {
		const rows = Object.values(data.tags).map((t) =>
			`${t.crown ? '👑 ' : ''}**${t.name}** → ${t.text} (${t.color})${t.owner ? ' • owner' : ''}`);
		const embed = new EmbedBuilder().setTitle('Clay tags')
			.setDescription(rows.join('\n').slice(0, 4000) || 'No custom tags yet.');
		return i.reply({ embeds: [embed], ephemeral: true });
	}

	if (sub === 'online') {
		prune();
		const names = [...online.values()].map((v) => v.name);
		return reply(names.length ? `**${names.length} online:** ${names.join(', ').slice(0, 1800)}` : 'Nobody is running Clay Client right now.');
	}

	const username = i.options.getString('username');
	if (!USERNAME_RE.test(username)) return reply('That does not look like a Roblox username (3–20 letters, numbers or _).');
	const key = username.toLowerCase();

	if (sub === 'remove') {
		if (!data.tags[key]) return reply(`${username} has no custom tag.`);
		delete data.tags[key];
		save();
		return reply(`Removed the tag from **${username}**.`);
	}

	if (sub === 'owner') {
		for (const [k, t] of Object.entries(data.tags)) if (t.owner) delete data.tags[k];
		data.tags[key] = { name: username, text: 'OWNER', color: OWNER_COLOR, crown: true, owner: true };
		save();
		return reply(`👑 **${username}** is now the OWNER (any previous owner was cleared).`);
	}

	if (sub === 'tag') {
		const text = i.options.getString('text').replace(/[\u0000-\u001f\u007f]/g, '').trim();
		if (!text || text.length > 20) return reply('Tag text must be 1–20 characters.');
		const color = parseColor(i.options.getString('color'));
		if (!color) return reply('Color must be a hex like `#ff66cc` or one of: ' + Object.keys(COLORS).join(', '));
		const crown = i.options.getBoolean('crown') === true;
		data.tags[key] = { name: username, text, color, crown, owner: false };
		save();
		return reply(`**${username}** now shows **${text}** (${color})${crown ? ' with a crown' : ''}.`);
	}
});

client.login(DISCORD_TOKEN);
