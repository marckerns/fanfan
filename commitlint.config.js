// 格式：<emoji> type(scope): subject
// type 与 emoji 均来自 https://github.com/carloscuesta/gitmoji
// 每个 type 对应唯一 emoji（1:1）

const norm = (s) => s?.replace(/️/g, '').trim() ?? '';

// emoji → gitmoji name（即 type）
const EMOJI_TYPE = {
  '🎨': 'art',
  '⚡': 'zap',
  '🔥': 'fire',
  '🐛': 'bug',
  '🚑': 'ambulance',
  '✨': 'sparkles',
  '📝': 'memo',
  '🚀': 'rocket',
  '💄': 'lipstick',
  '🎉': 'tada',
  '✅': 'white-check-mark',
  '🔒': 'lock',
  '🔐': 'closed-lock-with-key',
  '🔖': 'bookmark',
  '🚨': 'rotating-light',
  '🚧': 'construction',
  '💚': 'green-heart',
  '⬇': 'arrow-down',
  '⬆': 'arrow-up',
  '📌': 'pushpin',
  '👷': 'construction-worker',
  '📈': 'chart-with-upwards-trend',
  '♻': 'recycle',
  '➕': 'heavy-plus-sign',
  '➖': 'heavy-minus-sign',
  '🔧': 'wrench',
  '🔨': 'hammer',
  '🌐': 'globe-with-meridians',
  '✏': 'pencil2',
  '💩': 'poop',
  '⏪': 'rewind',
  '🔀': 'twisted-rightwards-arrows',
  '📦': 'package',
  '👽': 'alien',
  '🚚': 'truck',
  '📄': 'page-facing-up',
  '💥': 'boom',
  '🍱': 'bento',
  '♿': 'wheelchair',
  '💡': 'bulb',
  '🍻': 'beers',
  '💬': 'speech-balloon',
  '🗃': 'card-file-box',
  '🔊': 'loud-sound',
  '🔇': 'mute',
  '👥': 'busts-in-silhouette',
  '🚸': 'children-crossing',
  '🏗': 'building-construction',
  '📱': 'iphone',
  '🤡': 'clown-face',
  '🥚': 'egg',
  '🙈': 'see-no-evil',
  '📸': 'camera-flash',
  '⚗': 'alembic',
  '🔍': 'mag',
  '🏷': 'label',
  '🌱': 'seedling',
  '🚩': 'triangular-flag-on-post',
  '🥅': 'goal-net',
  '💫': 'dizzy',
  '🗑': 'wastebasket',
  '🛂': 'passport-control',
  '🩹': 'adhesive-bandage',
  '🧐': 'monocle-face',
  '⚰': 'coffin',
  '🧪': 'test-tube',
  '👔': 'necktie',
  '🩺': 'stethoscope',
  '🧱': 'bricks',
  '🧑‍💻': 'technologist',
  '💸': 'money-with-wings',
  '🧵': 'thread',
  '🦺': 'safety-vest',
  '✈': 'airplane',
  '🦖': 't-rex',
};

// 反转为 type → [emoji]，供 type-enum 和配对校验使用
const TYPE_EMOJI = Object.fromEntries(
  Object.entries(EMOJI_TYPE).map(([emoji, type]) => [type, [emoji]])
);

module.exports = {
  parserPreset: {
    parserOpts: {
      headerPattern:
        /^([\u{1F000}-\u{1FAFF}\u{2300}-\u{2BFF}]️?)\s([\w-]+)(?:\((\S+)\))?!?:\s(.+)/u,
      headerCorrespondence: ['emoji', 'type', 'scope', 'subject'],
    },
  },
  plugins: [
    {
      rules: {
        'emoji-type-match': ({ emoji, type }) => {
          const allowed = TYPE_EMOJI[type];
          if (!allowed) return [true];
          const ok = allowed.map(norm).includes(norm(emoji));
          return [
            ok,
            `"${emoji}" 与 type "${type}" 不匹配，应为: ${allowed[0]}`,
          ];
        },
      },
    },
  ],
  rules: {
    'emoji-type-match': [2, 'always'],
    'type-enum': [2, 'always', Object.keys(TYPE_EMOJI)],
    'type-empty': [2, 'never'],
    'scope-case': [2, 'always', 'lower-case'],
    'subject-empty': [2, 'never'],
    'subject-case': [0],
    'header-max-length': [2, 'always', 72],
    'body-leading-blank': [1, 'always'],
    'footer-leading-blank': [1, 'always'],
  },
};
