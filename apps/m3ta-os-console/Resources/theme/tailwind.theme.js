// BAMA: merge into tailwind.config theme.extend (shadcn convention; darkMode: 'class')
const v = n => `hsl(var(--${n}))`;
module.exports = { darkMode: ['class'], theme: { extend: {
  colors: { border:v('border'), input:v('input'), ring:v('ring'), background:v('background'), foreground:v('foreground'),
    primary:{DEFAULT:v('primary'),foreground:v('primary-foreground')}, secondary:{DEFAULT:v('secondary'),foreground:v('secondary-foreground')},
    destructive:{DEFAULT:v('destructive'),foreground:v('destructive-foreground')}, muted:{DEFAULT:v('muted'),foreground:v('muted-foreground')},
    accent:{DEFAULT:v('accent'),foreground:v('accent-foreground')}, popover:{DEFAULT:v('popover'),foreground:v('popover-foreground')},
    card:{DEFAULT:v('card'),foreground:v('card-foreground')},
    chart:{1:v('chart-1'),2:v('chart-2'),3:v('chart-3'),4:v('chart-4'),5:v('chart-5')},
    tmw:{"onyx": "#0E0A12", "onyx-raised": "#1B1422", "line": "#3A2C48", "cosmic-red": "#F0505A", "cosmic-red-deep": "#A01628", "violet-glow": "#B48CF2", "violet-deep": "#5B2C9E", "lightbody": "#FBF6EE", "pearl": "#EDE4F5", "muted": "#BDB2C8", "success": "#5CC08E", "alert": "#FF9F6B", "ink-on-light": "#0E0A12", "white": "#FFFFFF"} },
  borderRadius:{ lg:'var(--radius)', md:'calc(var(--radius) - 4px)', sm:'calc(var(--radius) - 6px)' },
  fontFamily:{ sans:['Inter','system-ui','sans-serif'] },
  backgroundImage:{ nebula:'var(--tmw-nebula)' },
}}};
