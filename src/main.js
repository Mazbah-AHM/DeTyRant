import * as pc from "playcanvas";

const canvas = document.getElementById("application");

const ui = {
  health: document.getElementById("health"),
  streak: document.getElementById("streak"),
  weaponName: document.getElementById("weapon-name"),
  ammo: document.getElementById("ammo"),
  reserve: document.getElementById("reserve"),
  timer: document.getElementById("timer"),
  kills: document.getElementById("kills"),
  deaths: document.getElementById("deaths"),
  leaderboard: document.getElementById("leaderboard-list"),
  killFeed: document.getElementById("kill-feed"),
  crosshair: document.getElementById("crosshair"),
  damageFlash: document.getElementById("damage-flash"),
  startScreen: document.getElementById("start-screen"),
  startButton: document.getElementById("start-button"),
  respawnBanner: document.getElementById("respawn-banner"),
  matchOver: document.getElementById("match-over"),
  winnerLine: document.getElementById("winner-line"),
  summaryLine: document.getElementById("summary-line"),
  restartButton: document.getElementById("restart-button"),
};

const CONFIG = {
  matchSeconds: 8 * 60,
  killLimit: 30,
  playerHealth: 100,
  botHealth: 100,
  playerRespawn: 2.4,
  botRespawn: 3.1,
  moveSpeed: 7.2,
  sprintSpeed: 10.3,
  acceleration: 30,
  friction: 18,
  mouseSensitivity: 0.0023,
  killRewardHeal: 18,
  killRewardAmmo: 0.4,
  floorY: 0,
  playerEyeHeight: 1.58,
  botEyeHeight: 1.35,
  playerRadius: 0.58,
  botRadius: 0.62,
};

const WEAPONS = {
  pistol: {
    id: "pistol",
    label: "VX Pistol",
    damage: 34,
    headshot: 1.55,
    fireRate: 3.3,
    magazine: 12,
    reload: 1.25,
    range: 60,
    spread: 0.007,
    moveSpread: 0.014,
    bloomPerShot: 0.1,
    recoilPitch: 0.018,
    recoilYaw: 0.008,
    auto: false,
    color: "#ffe59f",
  },
  smg: {
    id: "smg",
    label: "Ion SMG",
    damage: 16,
    headshot: 1.35,
    fireRate: 11.6,
    magazine: 24,
    reload: 1.45,
    range: 42,
    spread: 0.013,
    moveSpread: 0.022,
    bloomPerShot: 0.05,
    recoilPitch: 0.007,
    recoilYaw: 0.012,
    auto: true,
    color: "#93f6ff",
  },
  rifle: {
    id: "rifle",
    label: "Pulse Rifle",
    damage: 28,
    headshot: 1.45,
    fireRate: 7.2,
    magazine: 20,
    reload: 1.65,
    range: 72,
    spread: 0.009,
    moveSpread: 0.016,
    bloomPerShot: 0.065,
    recoilPitch: 0.011,
    recoilYaw: 0.01,
    auto: true,
    color: "#79e0ff",
  },
};

const BOT_NAMES = [
  "Aegis-7",
  "Nova Trace",
  "Cipher Echo",
  "Vector Bloom",
  "Helix-9",
  "Spectra Unit",
  "Zero Drift",
  "Quartz Shade",
];

const BOT_COLORS = [
  [0.36, 0.9, 1],
  [0.48, 0.78, 1],
  [0.56, 0.68, 1],
  [0.45, 0.95, 0.87],
  [0.85, 0.68, 1],
];

const app = new pc.Application(canvas, {
  elementInput: new pc.ElementInput(canvas),
  mouse: new pc.Mouse(canvas),
  keyboard: new pc.Keyboard(window),
  touch: "ontouchstart" in window ? new pc.TouchDevice(canvas) : null,
});

app.start();
app.setCanvasFillMode(pc.FILLMODE_FILL_WINDOW);
app.setCanvasResolution(pc.RESOLUTION_AUTO);
app.scene.ambientLight = new pc.Color(0.18, 0.21, 0.28);
app.scene.exposure = 1.26;
app.graphicsDevice.maxPixelRatio = Math.min(window.devicePixelRatio || 1, 1.5);

window.addEventListener("resize", () => app.resizeCanvas());

const worldRoot = new pc.Entity("world-root");
const dynamicRoot = new pc.Entity("dynamic-root");
const effectsRoot = new pc.Entity("effects-root");
app.root.addChild(worldRoot);
app.root.addChild(dynamicRoot);
app.root.addChild(effectsRoot);

const movementColliders = [];
const sightColliders = [];
const animatedPanels = [];
const movingShips = [];
const tracers = [];
const pulses = [];
const killFeedEntries = [];

const tempVecA = new pc.Vec3();
const tempVecB = new pc.Vec3();
const tempVecC = new pc.Vec3();

const game = {
  active: false,
  over: false,
  timeRemaining: CONFIG.matchSeconds,
  uiRefresh: 0,
};

const input = {
  firing: false,
  fireConsumed: false,
};

const spawnPoints = [
  new pc.Vec3(-20, 0, -18),
  new pc.Vec3(0, 0, -20),
  new pc.Vec3(20, 0, -18),
  new pc.Vec3(-20, 0, 18),
  new pc.Vec3(0, 0, 20),
  new pc.Vec3(20, 0, 18),
  new pc.Vec3(-22, 0, 0),
  new pc.Vec3(22, 0, 0),
];

const navPoints = [
  new pc.Vec3(-18, 0, -12),
  new pc.Vec3(-18, 0, 12),
  new pc.Vec3(18, 0, -12),
  new pc.Vec3(18, 0, 12),
  new pc.Vec3(-10, 0, -16),
  new pc.Vec3(-10, 0, 16),
  new pc.Vec3(10, 0, -16),
  new pc.Vec3(10, 0, 16),
  new pc.Vec3(-7, 0, 0),
  new pc.Vec3(7, 0, 0),
  new pc.Vec3(0, 0, -8),
  new pc.Vec3(0, 0, 8),
  new pc.Vec3(-14, 0, 0),
  new pc.Vec3(14, 0, 0),
  new pc.Vec3(0, 0, -16),
  new pc.Vec3(0, 0, 16),
];

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function rand(min, max) {
  return Math.random() * (max - min) + min;
}

function choose(items) {
  return items[Math.floor(Math.random() * items.length)];
}

function formatTime(totalSeconds) {
  const seconds = Math.max(0, Math.ceil(totalSeconds));
  const minutes = Math.floor(seconds / 60);
  const rem = seconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(rem).padStart(2, "0")}`;
}

function color255(r, g, b) {
  return new pc.Color(r / 255, g / 255, b / 255);
}

function colorFromArray(rgb) {
  return new pc.Color(rgb[0], rgb[1], rgb[2]);
}

function makeMaterial({
  diffuse,
  emissive = null,
  emissiveIntensity = 0,
  opacity = 1,
  metalness = 0.3,
  shininess = 60,
  cull = pc.CULLFACE_BACK,
}) {
  const material = new pc.StandardMaterial();
  material.diffuse = diffuse.clone ? diffuse.clone() : diffuse;
  material.emissive = emissive ? (emissive.clone ? emissive.clone() : emissive) : new pc.Color(0, 0, 0);
  material.emissiveIntensity = emissiveIntensity;
  material.opacity = opacity;
  material.useMetalness = true;
  material.metalness = metalness;
  material.shininess = shininess;
  material.cull = cull;
  if (opacity < 1) {
    material.blendType = pc.BLEND_NORMAL;
  }
  material.update();
  return material;
}

const materials = {
  floor: makeMaterial({
    diffuse: color255(29, 39, 58),
    emissive: color255(8, 16, 28),
    emissiveIntensity: 0.28,
    metalness: 0.82,
    shininess: 82,
  }),
  panel: makeMaterial({
    diffuse: color255(210, 222, 238),
    emissive: color255(12, 20, 32),
    emissiveIntensity: 0.14,
    metalness: 0.34,
    shininess: 74,
  }),
  trim: makeMaterial({
    diffuse: color255(32, 48, 70),
    emissive: color255(93, 228, 255),
    emissiveIntensity: 0.65,
    metalness: 0.22,
    shininess: 92,
  }),
  wallDark: makeMaterial({
    diffuse: color255(37, 48, 67),
    emissive: color255(7, 12, 21),
    emissiveIntensity: 0.16,
    metalness: 0.7,
    shininess: 88,
  }),
  glass: makeMaterial({
    diffuse: color255(70, 129, 158),
    emissive: color255(87, 191, 225),
    emissiveIntensity: 0.22,
    opacity: 0.22,
    metalness: 0.12,
    shininess: 100,
    cull: pc.CULLFACE_NONE,
  }),
  reactor: makeMaterial({
    diffuse: color255(26, 34, 52),
    emissive: color255(57, 221, 255),
    emissiveIntensity: 1.3,
    metalness: 0.12,
    shininess: 96,
  }),
  cover: makeMaterial({
    diffuse: color255(68, 82, 104),
    emissive: color255(15, 21, 36),
    emissiveIntensity: 0.22,
    metalness: 0.64,
    shininess: 72,
  }),
  accentWarm: makeMaterial({
    diffuse: color255(130, 114, 78),
    emissive: color255(255, 190, 106),
    emissiveIntensity: 0.65,
    metalness: 0.22,
    shininess: 82,
  }),
  star: makeMaterial({
    diffuse: color255(250, 252, 255),
    emissive: color255(210, 236, 255),
    emissiveIntensity: 1.5,
    metalness: 0,
    shininess: 2,
    cull: pc.CULLFACE_NONE,
  }),
  backdrop: makeMaterial({
    diffuse: color255(4, 7, 14),
    emissive: color255(0, 0, 0),
    emissiveIntensity: 0,
    metalness: 0,
    shininess: 2,
    cull: pc.CULLFACE_NONE,
  }),
  ship: makeMaterial({
    diffuse: color255(152, 170, 208),
    emissive: color255(35, 102, 135),
    emissiveIntensity: 0.3,
    metalness: 0.58,
    shininess: 84,
  }),
  viewNeutral: makeMaterial({
    diffuse: color255(205, 212, 225),
    emissive: color255(19, 35, 48),
    emissiveIntensity: 0.08,
    metalness: 0.18,
    shininess: 88,
  }),
  viewAccent: makeMaterial({
    diffuse: color255(90, 215, 246),
    emissive: color255(90, 215, 246),
    emissiveIntensity: 1.1,
    metalness: 0.08,
    shininess: 90,
  }),
};

function applyMaterial(entity, material) {
  if (!entity.render) {
    return;
  }
  entity.render.meshInstances.forEach((meshInstance) => {
    meshInstance.material = material;
  });
}

function addAabb(center, scale, blocksMovement = true, blocksSight = true) {
  const box = {
    minX: center.x - scale.x * 0.5,
    maxX: center.x + scale.x * 0.5,
    minY: center.y - scale.y * 0.5,
    maxY: center.y + scale.y * 0.5,
    minZ: center.z - scale.z * 0.5,
    maxZ: center.z + scale.z * 0.5,
  };
  if (blocksMovement) {
    movementColliders.push(box);
  }
  if (blocksSight) {
    sightColliders.push(box);
  }
}

function createRenderEntity(type, position, scale, material, parent = worldRoot) {
  const entity = new pc.Entity(type);
  entity.addComponent("render", { type });
  entity.setLocalPosition(position);
  entity.setLocalScale(scale);
  parent.addChild(entity);
  applyMaterial(entity, material);
  entity.render.castShadows = true;
  entity.render.receiveShadows = true;
  return entity;
}

function createBox(position, scale, material, options = {}) {
  const entity = createRenderEntity("box", position, scale, material, options.parent || worldRoot);
  if (options.rotation) {
    entity.setLocalEulerAngles(options.rotation[0], options.rotation[1], options.rotation[2]);
  }
  if (options.name) {
    entity.name = options.name;
  }
  if (options.shadowless) {
    entity.render.castShadows = false;
    entity.render.receiveShadows = false;
  }
  if (options.collider) {
    addAabb(position, scale, options.blocksMovement !== false, options.blocksSight !== false);
  }
  return entity;
}

function createCylinder(position, scale, material, options = {}) {
  const entity = createRenderEntity("cylinder", position, scale, material, options.parent || worldRoot);
  if (options.rotation) {
    entity.setLocalEulerAngles(options.rotation[0], options.rotation[1], options.rotation[2]);
  }
  if (options.collider) {
    addAabb(position, scale, options.blocksMovement !== false, options.blocksSight !== false);
  }
  if (options.shadowless) {
    entity.render.castShadows = false;
    entity.render.receiveShadows = false;
  }
  return entity;
}

function createSphere(position, scale, material, options = {}) {
  const entity = createRenderEntity("sphere", position, scale, material, options.parent || worldRoot);
  if (options.shadowless) {
    entity.render.castShadows = false;
    entity.render.receiveShadows = false;
  }
  return entity;
}

function attachShape(parent, type, position, scale, material, options = {}) {
  const entity = new pc.Entity(type);
  entity.addComponent("render", { type });
  entity.setLocalPosition(position);
  entity.setLocalScale(scale);
  if (options.rotation) {
    entity.setLocalEulerAngles(options.rotation[0], options.rotation[1], options.rotation[2]);
  }
  parent.addChild(entity);
  applyMaterial(entity, material);
  entity.render.castShadows = options.castShadows === true;
  entity.render.receiveShadows = options.receiveShadows === true;
  return entity;
}

function buildArena() {
  createBox(new pc.Vec3(0, -0.5, 0), new pc.Vec3(56, 1, 56), materials.floor);
  createBox(new pc.Vec3(0, 6, 0), new pc.Vec3(56, 0.5, 56), materials.wallDark, {
    shadowless: true,
  });

  createBox(new pc.Vec3(-27.75, 2.25, 0), new pc.Vec3(1.5, 4.8, 56), materials.panel, {
    collider: true,
  });
  createBox(new pc.Vec3(27.75, 2.25, 0), new pc.Vec3(1.5, 4.8, 56), materials.panel, {
    collider: true,
  });

  createBox(new pc.Vec3(-19, 2.25, -27.75), new pc.Vec3(18, 4.8, 1.5), materials.panel, {
    collider: true,
  });
  createBox(new pc.Vec3(19, 2.25, -27.75), new pc.Vec3(18, 4.8, 1.5), materials.panel, {
    collider: true,
  });
  createBox(new pc.Vec3(0, 2.35, -27.15), new pc.Vec3(15.5, 4.1, 0.24), materials.glass, {
    collider: true,
    shadowless: true,
  });

  createBox(new pc.Vec3(-19, 2.25, 27.75), new pc.Vec3(18, 4.8, 1.5), materials.panel, {
    collider: true,
  });
  createBox(new pc.Vec3(19, 2.25, 27.75), new pc.Vec3(18, 4.8, 1.5), materials.panel, {
    collider: true,
  });
  createBox(new pc.Vec3(0, 2.35, 27.15), new pc.Vec3(15.5, 4.1, 0.24), materials.glass, {
    collider: true,
    shadowless: true,
  });

  [
    new pc.Vec3(-24.5, 2.4, -24.5),
    new pc.Vec3(24.5, 2.4, -24.5),
    new pc.Vec3(-24.5, 2.4, 24.5),
    new pc.Vec3(24.5, 2.4, 24.5),
  ].forEach((position) => {
    createBox(position, new pc.Vec3(2, 4.6, 2), materials.wallDark, { collider: true });
  });

  createCylinder(new pc.Vec3(0, 0.85, 0), new pc.Vec3(5.2, 1.6, 5.2), materials.cover, {
    collider: true,
  });
  createCylinder(new pc.Vec3(0, 2.75, 0), new pc.Vec3(2.5, 3.6, 2.5), materials.reactor, {
    collider: true,
  });
  const coreRing = createCylinder(new pc.Vec3(0, 4.45, 0), new pc.Vec3(4.4, 0.12, 4.4), materials.trim, {
    shadowless: true,
  });
  animatedPanels.push({ entity: coreRing, axis: "y", speed: 24 });

  [
    new pc.Vec3(-7.4, 1.15, -7.4),
    new pc.Vec3(7.4, 1.15, -7.4),
    new pc.Vec3(-7.4, 1.15, 7.4),
    new pc.Vec3(7.4, 1.15, 7.4),
  ].forEach((position) => {
    createBox(position, new pc.Vec3(3.4, 2.2, 3.4), materials.cover, { collider: true });
    const strip = createBox(
      new pc.Vec3(position.x, position.y + 1.15, position.z),
      new pc.Vec3(2.8, 0.1, 0.2),
      materials.trim,
      { shadowless: true }
    );
    animatedPanels.push({ entity: strip, pulse: rand(0, Math.PI * 2) });
  });

  [
    new pc.Vec3(-14.5, 1.65, -9.5),
    new pc.Vec3(-14.5, 1.65, 9.5),
    new pc.Vec3(14.5, 1.65, -9.5),
    new pc.Vec3(14.5, 1.65, 9.5),
  ].forEach((position) => {
    createBox(position, new pc.Vec3(1.3, 3.2, 10.2), materials.panel, { collider: true });
  });

  [
    new pc.Vec3(-10.5, 1.4, -17),
    new pc.Vec3(10.5, 1.4, -17),
    new pc.Vec3(-10.5, 1.4, 17),
    new pc.Vec3(10.5, 1.4, 17),
    new pc.Vec3(-18.5, 1.4, 0),
    new pc.Vec3(18.5, 1.4, 0),
  ].forEach((position) => {
    createBox(position, new pc.Vec3(3.6, 2.8, 2.2), materials.cover, { collider: true });
    createBox(
      new pc.Vec3(position.x, position.y + 1.4, position.z),
      new pc.Vec3(3, 0.1, 0.18),
      materials.trim,
      { shadowless: true }
    );
  });

  for (let x = -20; x <= 20; x += 10) {
    createBox(new pc.Vec3(x, 0.03, -23), new pc.Vec3(3.6, 0.06, 0.22), materials.trim, {
      shadowless: true,
    });
    createBox(new pc.Vec3(x, 0.03, 23), new pc.Vec3(3.6, 0.06, 0.22), materials.trim, {
      shadowless: true,
    });
  }

  [
    [-12, 2.2, -26.6],
    [12, 2.2, -26.6],
    [-12, 2.2, 26.6],
    [12, 2.2, 26.6],
  ].forEach(([x, y, z]) => {
    createBox(new pc.Vec3(x, y, z), new pc.Vec3(1.8, 0.35, 0.25), materials.accentWarm, {
      shadowless: true,
    });
  });
}

function buildSpaceBackdrop() {
  const dome = createSphere(new pc.Vec3(0, 0, 0), new pc.Vec3(160, 160, 160), materials.backdrop, {
    shadowless: true,
  });
  dome.setLocalScale(-160, 160, 160);

  for (let index = 0; index < 120; index += 1) {
    const theta = rand(0, Math.PI * 2);
    const phi = rand(0.2, Math.PI - 0.2);
    const radius = rand(95, 120);
    const x = Math.sin(phi) * Math.cos(theta) * radius;
    const y = Math.cos(phi) * radius;
    const z = Math.sin(phi) * Math.sin(theta) * radius;
    createSphere(new pc.Vec3(x, y, z), new pc.Vec3(rand(0.12, 0.42), rand(0.12, 0.42), rand(0.12, 0.42)), materials.star, {
      shadowless: true,
    });
  }

  for (let index = 0; index < 3; index += 1) {
    const ship = new pc.Entity(`ship-${index}`);
    worldRoot.addChild(ship);
    ship.setLocalPosition(rand(-18, 18), rand(2, 8), index === 0 ? -46 : index === 1 ? 43 : -54);

    const body = attachShape(ship, "box", new pc.Vec3(0, 0, 0), new pc.Vec3(2.8, 0.5, 6.8), materials.ship);
    body.render.castShadows = false;
    const wingA = attachShape(ship, "box", new pc.Vec3(2.2, 0, 0.4), new pc.Vec3(2.8, 0.12, 1.8), materials.trim);
    const wingB = attachShape(ship, "box", new pc.Vec3(-2.2, 0, 0.4), new pc.Vec3(2.8, 0.12, 1.8), materials.trim);
    wingA.render.castShadows = false;
    wingA.render.receiveShadows = false;
    wingB.render.castShadows = false;
    wingB.render.receiveShadows = false;

    movingShips.push({
      entity: ship,
      baseX: ship.getLocalPosition().x,
      baseY: ship.getLocalPosition().y,
      baseZ: ship.getLocalPosition().z,
      speed: rand(0.35, 0.8),
      amplitude: rand(8, 16),
      phase: rand(0, Math.PI * 2),
    });
  }
}

function buildLighting() {
  const mainLight = new pc.Entity("main-light");
  mainLight.addComponent("light", {
    type: "directional",
    color: new pc.Color(0.88, 0.92, 1),
    intensity: 1.4,
    castShadows: true,
    shadowDistance: 90,
    shadowResolution: 1024,
  });
  mainLight.setLocalEulerAngles(56, 32, 0);
  app.root.addChild(mainLight);

  [
    { pos: new pc.Vec3(0, 4.5, 0), color: new pc.Color(0.33, 0.94, 1), intensity: 3.4, range: 20 },
    { pos: new pc.Vec3(-18, 4.3, -18), color: new pc.Color(0.28, 0.62, 1), intensity: 1.4, range: 18 },
    { pos: new pc.Vec3(18, 4.3, 18), color: new pc.Color(0.28, 0.62, 1), intensity: 1.4, range: 18 },
    { pos: new pc.Vec3(-18, 4.3, 18), color: new pc.Color(0.25, 0.95, 0.86), intensity: 1.2, range: 14 },
    { pos: new pc.Vec3(18, 4.3, -18), color: new pc.Color(1, 0.72, 0.47), intensity: 1.1, range: 14 },
    { pos: new pc.Vec3(-10, 3.8, 0), color: new pc.Color(0.22, 0.85, 1), intensity: 1.1, range: 13 },
    { pos: new pc.Vec3(10, 3.8, 0), color: new pc.Color(0.22, 0.85, 1), intensity: 1.1, range: 13 },
    { pos: new pc.Vec3(0, 3.8, -14), color: new pc.Color(0.38, 0.8, 1), intensity: 1.05, range: 13 },
    { pos: new pc.Vec3(0, 3.8, 14), color: new pc.Color(0.38, 0.8, 1), intensity: 1.05, range: 13 },
  ].forEach((lightData) => {
    const light = new pc.Entity("omni-light");
    light.addComponent("light", {
      type: "omni",
      color: lightData.color,
      intensity: lightData.intensity,
      range: lightData.range,
      castShadows: false,
    });
    light.setLocalPosition(lightData.pos);
    app.root.addChild(light);
  });
}

buildArena();
buildSpaceBackdrop();
buildLighting();

function createPlayer() {
  const root = new pc.Entity("player-root");
  root.setLocalPosition(0, CONFIG.floorY, 0);
  app.root.addChild(root);

  const pitchPivot = new pc.Entity("player-pitch");
  pitchPivot.setLocalPosition(0, CONFIG.playerEyeHeight, 0);
  root.addChild(pitchPivot);

  const camera = new pc.Entity("player-camera");
  camera.addComponent("camera", {
    clearColor: color255(3, 6, 13),
    fov: 78,
    nearClip: 0.05,
    farClip: 220,
  });
  pitchPivot.addChild(camera);

  const inventory = {};
  Object.values(WEAPONS).forEach((weapon) => {
    inventory[weapon.id] = {
      magazine: weapon.magazine,
      reserve: Number.POSITIVE_INFINITY,
    };
  });

  return {
    type: "player",
    name: "DeTyrant",
    entity: root,
    pitchPivot,
    camera,
    eyeHeight: CONFIG.playerEyeHeight,
    radius: CONFIG.playerRadius,
    health: CONFIG.playerHealth,
    alive: true,
    velocityX: 0,
    velocityZ: 0,
    yaw: 0,
    pitch: 0,
    kills: 0,
    deaths: 0,
    streak: 0,
    respawnTimer: 0,
    reloadTimer: 0,
    reloadingWeapon: null,
    shotCooldown: 0,
    spawnShield: 0,
    currentWeapon: "rifle",
    inventory,
    spreadBloom: 0,
    damageFlash: 0,
    hitMarker: 0,
  };
}

function createViewModel(camera) {
  const root = new pc.Entity("view-model");
  root.setLocalPosition(0.34, -0.34, -0.84);
  camera.addChild(root);

  const body = attachShape(root, "box", new pc.Vec3(0, 0, 0.12), new pc.Vec3(0.24, 0.16, 0.68), materials.viewNeutral);
  const barrel = attachShape(root, "box", new pc.Vec3(0.02, 0.02, -0.34), new pc.Vec3(0.07, 0.07, 0.5), materials.viewNeutral);
  const stock = attachShape(root, "box", new pc.Vec3(-0.02, -0.02, 0.38), new pc.Vec3(0.13, 0.18, 0.26), materials.viewNeutral);
  const accent = attachShape(root, "box", new pc.Vec3(0, 0.07, -0.08), new pc.Vec3(0.15, 0.04, 0.46), materials.viewAccent);
  const muzzle = attachShape(root, "box", new pc.Vec3(0.02, 0.02, -0.64), new pc.Vec3(0.1, 0.1, 0.18), materials.accentWarm);
  muzzle.enabled = false;

  [body, barrel, stock, accent, muzzle].forEach((part) => {
    part.render.castShadows = false;
    part.render.receiveShadows = false;
  });

  return {
    root,
    body,
    barrel,
    stock,
    accent,
    muzzle,
    basePosition: new pc.Vec3(0.34, -0.34, -0.84),
    kick: 0,
    flashTimer: 0,
  };
}

function createBot(index) {
  const root = new pc.Entity(`bot-${index}`);
  dynamicRoot.addChild(root);

  const core = colorFromArray(BOT_COLORS[index % BOT_COLORS.length]);
  const bodyMaterial = makeMaterial({
    diffuse: color255(198, 212, 228),
    emissive: new pc.Color(core.r * 0.25, core.g * 0.25, core.b * 0.25),
    emissiveIntensity: 0.35,
    metalness: 0.28,
    shininess: 88,
  });
  const accentMaterial = makeMaterial({
    diffuse: core,
    emissive: core,
    emissiveIntensity: 1.2,
    metalness: 0.08,
    shininess: 92,
  });
  const visorMaterial = makeMaterial({
    diffuse: color255(22, 34, 52),
    emissive: core,
    emissiveIntensity: 0.6,
    metalness: 0.18,
    shininess: 94,
  });

  attachShape(root, "cylinder", new pc.Vec3(0, 1.05, 0), new pc.Vec3(0.74, 1.5, 0.74), bodyMaterial);
  attachShape(root, "sphere", new pc.Vec3(0, 1.95, 0), new pc.Vec3(0.48, 0.48, 0.48), visorMaterial);
  attachShape(root, "box", new pc.Vec3(0, 1.42, 0.41), new pc.Vec3(0.44, 0.12, 0.1), accentMaterial);
  attachShape(root, "box", new pc.Vec3(0.42, 1.26, 0), new pc.Vec3(0.12, 0.45, 0.12), accentMaterial);
  attachShape(root, "box", new pc.Vec3(-0.42, 1.26, 0), new pc.Vec3(0.12, 0.45, 0.12), accentMaterial);

  root.children.forEach((child) => {
    child.render.castShadows = true;
    child.render.receiveShadows = true;
  });

  return {
    type: "bot",
    name: BOT_NAMES[index % BOT_NAMES.length],
    entity: root,
    accentMaterial,
    eyeHeight: CONFIG.botEyeHeight,
    radius: CONFIG.botRadius,
    health: CONFIG.botHealth,
    alive: false,
    velocityX: 0,
    velocityZ: 0,
    kills: 0,
    deaths: 0,
    streak: 0,
    respawnTimer: rand(0.2, 1.2),
    shotCooldown: rand(0.3, 0.8),
    thinkTimer: rand(0.15, 0.45),
    wanderTarget: choose(navPoints).clone(),
    strafeDir: Math.random() > 0.5 ? 1 : -1,
    strafeTimer: rand(0.7, 1.8),
    currentTarget: null,
    accuracy: rand(0.62, 0.82),
    weapon: {
      damage: rand(18, 24),
      fireRate: rand(4.6, 6.3),
      range: rand(40, 55),
    },
    flashTimer: 0,
    spawnShield: 0,
  };
}

const player = createPlayer();
const viewModel = createViewModel(player.camera);
const bots = Array.from({ length: 5 }, (_, index) => createBot(index));

function allActors() {
  return [player, ...bots];
}

function getActorPosition(actor) {
  return actor.entity.getPosition();
}

function getActorEyePosition(actor) {
  const position = actor.entity.getPosition();
  return new pc.Vec3(position.x, position.y + actor.eyeHeight, position.z);
}

function getActorChestPosition(actor) {
  const position = actor.entity.getPosition();
  return new pc.Vec3(position.x, position.y + actor.eyeHeight - 0.45, position.z);
}

function getPlayerWeaponState() {
  return player.inventory[player.currentWeapon];
}

function updateWeaponPresentation() {
  const weapon = WEAPONS[player.currentWeapon];
  ui.weaponName.textContent = weapon.label;

  if (weapon.id === "pistol") {
    viewModel.basePosition.set(0.27, -0.35, -0.64);
    viewModel.body.setLocalScale(0.16, 0.12, 0.34);
    viewModel.body.setLocalPosition(0, -0.01, 0.08);
    viewModel.barrel.setLocalScale(0.05, 0.05, 0.28);
    viewModel.barrel.setLocalPosition(0.02, 0.01, -0.24);
    viewModel.stock.setLocalScale(0.09, 0.14, 0.12);
    viewModel.stock.setLocalPosition(-0.02, -0.03, 0.22);
    viewModel.accent.setLocalScale(0.1, 0.03, 0.18);
    viewModel.accent.setLocalPosition(0, 0.05, -0.01);
    applyMaterial(viewModel.accent, materials.accentWarm);
  } else if (weapon.id === "smg") {
    viewModel.basePosition.set(0.31, -0.34, -0.74);
    viewModel.body.setLocalScale(0.2, 0.14, 0.46);
    viewModel.body.setLocalPosition(0, 0, 0.07);
    viewModel.barrel.setLocalScale(0.05, 0.05, 0.4);
    viewModel.barrel.setLocalPosition(0.02, 0.02, -0.32);
    viewModel.stock.setLocalScale(0.1, 0.17, 0.18);
    viewModel.stock.setLocalPosition(-0.02, -0.02, 0.28);
    viewModel.accent.setLocalScale(0.12, 0.03, 0.32);
    viewModel.accent.setLocalPosition(0, 0.06, -0.05);
    applyMaterial(viewModel.accent, materials.trim);
  } else {
    viewModel.basePosition.set(0.33, -0.33, -0.79);
    viewModel.body.setLocalScale(0.22, 0.14, 0.54);
    viewModel.body.setLocalPosition(0, 0, 0.1);
    viewModel.barrel.setLocalScale(0.05, 0.05, 0.44);
    viewModel.barrel.setLocalPosition(0.02, 0.02, -0.34);
    viewModel.stock.setLocalScale(0.11, 0.15, 0.19);
    viewModel.stock.setLocalPosition(-0.02, -0.02, 0.34);
    viewModel.accent.setLocalScale(0.13, 0.03, 0.34);
    viewModel.accent.setLocalPosition(0, 0.06, -0.08);
    applyMaterial(viewModel.accent, materials.viewAccent);
  }

  viewModel.root.setLocalPosition(viewModel.basePosition);
}

function addKillFeed(text) {
  killFeedEntries.push({ text, time: 4.4 });
  if (killFeedEntries.length > 6) {
    killFeedEntries.shift();
  }
  renderKillFeed();
}

function renderKillFeed() {
  ui.killFeed.innerHTML = killFeedEntries.map((entry) => `<div class="kill-feed-entry">${entry.text}</div>`).join("");
}

function renderLeaderboard() {
  const ranking = allActors()
    .slice()
    .sort((left, right) => {
      if (right.kills !== left.kills) {
        return right.kills - left.kills;
      }
      return left.deaths - right.deaths;
    })
    .slice(0, 6);

  ui.leaderboard.innerHTML = ranking
    .map((actor) => {
      const isPlayer = actor === player;
      return `<div class="leaderboard-entry${isPlayer ? " player" : ""}">
        <span class="name">${actor.name}</span>
        <span>${actor.kills} / ${actor.deaths}</span>
      </div>`;
    })
    .join("");
}

function updateBanner() {
  if (game.over) {
    ui.respawnBanner.classList.add("hidden");
    return;
  }

  if (game.active && !player.alive) {
    ui.respawnBanner.textContent = `Reconstructing loadout in ${player.respawnTimer.toFixed(1)}s`;
    ui.respawnBanner.classList.remove("hidden");
    return;
  }

  if (game.active && document.pointerLockElement !== canvas) {
    ui.respawnBanner.textContent = "Click the arena to re-engage your uplink.";
    ui.respawnBanner.classList.remove("hidden");
    return;
  }

  ui.respawnBanner.classList.add("hidden");
}

function refreshHud(force = false) {
  const state = getPlayerWeaponState();
  const reserveText = state.reserve === Number.POSITIVE_INFINITY ? "INF" : String(state.reserve);

  ui.health.textContent = String(Math.max(0, Math.ceil(player.health)));
  ui.streak.textContent = String(player.streak);
  ui.ammo.textContent = String(state.magazine);
  ui.reserve.textContent = reserveText;
  ui.kills.textContent = String(player.kills);
  ui.deaths.textContent = String(player.deaths);
  ui.timer.textContent = formatTime(game.timeRemaining);
  ui.damageFlash.style.opacity = String(clamp(player.damageFlash, 0, 0.65));

  if (force || game.uiRefresh <= 0) {
    renderLeaderboard();
    game.uiRefresh = 0.15;
  }

  const spread = 10 + player.spreadBloom * 34 + clamp(Math.hypot(player.velocityX, player.velocityZ) * 0.9, 0, 10);
  ui.crosshair.style.setProperty("--gap", `${spread.toFixed(1)}px`);
  ui.crosshair.style.opacity = game.active && player.alive ? "1" : "0.55";
  ui.crosshair.style.filter = player.hitMarker > 0 ? "drop-shadow(0 0 14px rgba(255, 219, 90, 0.9))" : "";

  updateBanner();
}

function circleIntersectsAabb(x, z, radius, box) {
  const nearestX = clamp(x, box.minX, box.maxX);
  const nearestZ = clamp(z, box.minZ, box.maxZ);
  const dx = x - nearestX;
  const dz = z - nearestZ;
  return dx * dx + dz * dz < radius * radius;
}

function positionBlocked(actor, x, z) {
  for (const box of movementColliders) {
    if (circleIntersectsAabb(x, z, actor.radius, box)) {
      return true;
    }
  }

  for (const other of allActors()) {
    if (other === actor || !other.alive) {
      continue;
    }
    const otherPosition = getActorPosition(other);
    const dx = x - otherPosition.x;
    const dz = z - otherPosition.z;
    const minDistance = actor.radius + other.radius - 0.05;
    if (dx * dx + dz * dz < minDistance * minDistance) {
      return true;
    }
  }

  return false;
}

function moveActor(actor, deltaX, deltaZ) {
  const position = actor.entity.getPosition();
  const nextX = position.x + deltaX;
  const nextZ = position.z + deltaZ;

  if (!positionBlocked(actor, nextX, position.z)) {
    position.x = nextX;
  } else {
    actor.velocityX = 0;
  }

  if (!positionBlocked(actor, position.x, nextZ)) {
    position.z = nextZ;
  } else {
    actor.velocityZ = 0;
  }

  actor.entity.setPosition(position.x, CONFIG.floorY, position.z);
}

function rayAabbDistance(origin, direction, box, maxDistance) {
  let tMin = 0;
  let tMax = maxDistance;

  const axes = [
    ["x", box.minX, box.maxX],
    ["y", box.minY, box.maxY],
    ["z", box.minZ, box.maxZ],
  ];

  for (const [axis, min, max] of axes) {
    const o = origin[axis];
    const d = direction[axis];

    if (Math.abs(d) < 1e-6) {
      if (o < min || o > max) {
        return Number.POSITIVE_INFINITY;
      }
      continue;
    }

    const inverse = 1 / d;
    let t1 = (min - o) * inverse;
    let t2 = (max - o) * inverse;

    if (t1 > t2) {
      const swap = t1;
      t1 = t2;
      t2 = swap;
    }

    tMin = Math.max(tMin, t1);
    tMax = Math.min(tMax, t2);

    if (tMin > tMax) {
      return Number.POSITIVE_INFINITY;
    }
  }

  return tMin <= maxDistance ? tMin : Number.POSITIVE_INFINITY;
}

function raySphereDistance(origin, direction, center, radius, maxDistance) {
  const offsetX = origin.x - center.x;
  const offsetY = origin.y - center.y;
  const offsetZ = origin.z - center.z;
  const b = offsetX * direction.x + offsetY * direction.y + offsetZ * direction.z;
  const c = offsetX * offsetX + offsetY * offsetY + offsetZ * offsetZ - radius * radius;
  const h = b * b - c;
  if (h < 0) {
    return Number.POSITIVE_INFINITY;
  }

  const root = Math.sqrt(h);
  const near = -b - root;
  const far = -b + root;
  if (near > 0.001 && near <= maxDistance) {
    return near;
  }
  if (far > 0.001 && far <= maxDistance) {
    return far;
  }
  return Number.POSITIVE_INFINITY;
}

function lineOfSight(start, end) {
  tempVecA.sub2(end, start);
  const distance = tempVecA.length();
  if (distance <= 0.001) {
    return true;
  }
  tempVecA.mulScalar(1 / distance);

  for (const box of sightColliders) {
    const hitDistance = rayAabbDistance(start, tempVecA, box, distance);
    if (hitDistance !== Number.POSITIVE_INFINITY) {
      return false;
    }
  }
  return true;
}

function spawnTracer(start, end, hexColor, duration = 0.075, thickness = 0.05) {
  tempVecA.sub2(end, start);
  const length = tempVecA.length();
  if (length <= 0.05) {
    return;
  }

  const material = makeMaterial({
    diffuse: color255(255, 255, 255),
    emissive: color255(
      Number.parseInt(hexColor.slice(1, 3), 16),
      Number.parseInt(hexColor.slice(3, 5), 16),
      Number.parseInt(hexColor.slice(5, 7), 16)
    ),
    emissiveIntensity: 1.4,
    metalness: 0,
    shininess: 10,
    cull: pc.CULLFACE_NONE,
  });

  const tracer = createBox(
    new pc.Vec3((start.x + end.x) * 0.5, (start.y + end.y) * 0.5, (start.z + end.z) * 0.5),
    new pc.Vec3(thickness, thickness, length),
    material,
    { parent: effectsRoot, shadowless: true }
  );
  tracer.lookAt(end.x, end.y, end.z);
  tracers.push({ entity: tracer, material, life: duration, maxLife: duration });
}

function spawnPulse(position, material = materials.trim, duration = 0.18) {
  const pulse = createSphere(position, new pc.Vec3(0.18, 0.18, 0.18), material, {
    parent: effectsRoot,
    shadowless: true,
  });
  pulses.push({ entity: pulse, life: duration, maxLife: duration });
}

function chooseSpawn(actor) {
  let bestSpawn = spawnPoints[0];
  let bestScore = -Infinity;

  for (const spawn of spawnPoints) {
    let minDistance = Number.POSITIVE_INFINITY;
    for (const other of allActors()) {
      if (other === actor || !other.alive) {
        continue;
      }
      const otherPosition = getActorPosition(other);
      const dx = spawn.x - otherPosition.x;
      const dz = spawn.z - otherPosition.z;
      minDistance = Math.min(minDistance, Math.hypot(dx, dz));
    }
    if (minDistance > bestScore) {
      bestScore = minDistance;
      bestSpawn = spawn;
    }
  }

  return bestSpawn.clone();
}

function resetPlayerInventory() {
  Object.values(WEAPONS).forEach((weapon) => {
    player.inventory[weapon.id].magazine = weapon.magazine;
    player.inventory[weapon.id].reserve = Number.POSITIVE_INFINITY;
  });
}

function respawnActor(actor, initial = false) {
  const spawn = chooseSpawn(actor);
  actor.entity.setPosition(spawn.x, CONFIG.floorY, spawn.z);
  actor.health = actor === player ? CONFIG.playerHealth : CONFIG.botHealth;
  actor.alive = true;
  actor.respawnTimer = 0;
  actor.shotCooldown = actor === player ? 0 : rand(0.15, 0.45);
  actor.reloadTimer = 0;
  actor.reloadingWeapon = null;
  actor.spawnShield = actor === player ? 1.4 : 0.8;

  if (actor === player) {
    player.velocityX = 0;
    player.velocityZ = 0;
    resetPlayerInventory();
    const dirX = -spawn.x;
    const dirZ = -spawn.z;
    player.yaw = Math.atan2(-dirX, -dirZ);
    player.pitch = -0.02;
    if (initial) {
      player.currentWeapon = "rifle";
    }
    updateWeaponPresentation();
  } else {
    actor.entity.enabled = true;
    actor.currentTarget = null;
    actor.thinkTimer = rand(0.1, 0.35);
    actor.wanderTarget = choose(navPoints).clone();
  }
}

function scheduleRespawn(actor, delay) {
  actor.alive = false;
  actor.respawnTimer = delay;
  actor.shotCooldown = 0;
  if (actor !== player) {
    actor.entity.enabled = false;
  }
}

function onKill(attacker, target, weaponLabel, headshot = false) {
  target.deaths += 1;
  target.streak = 0;

  if (attacker && attacker !== target) {
    attacker.kills += 1;
    attacker.streak += 1;
    if (attacker === player) {
      player.health = Math.min(CONFIG.playerHealth, player.health + CONFIG.killRewardHeal);
      const state = getPlayerWeaponState();
      const weapon = WEAPONS[player.currentWeapon];
      state.magazine = Math.min(weapon.magazine, state.magazine + Math.ceil(weapon.magazine * CONFIG.killRewardAmmo));
      addKillFeed(`DeTyrant deleted ${target.name} with ${weaponLabel}${headshot ? " [critical]" : ""}.`);
    } else if (target === player) {
      addKillFeed(`${attacker.name} dropped DeTyrant with ${weaponLabel}${headshot ? " [critical]" : ""}.`);
    } else {
      addKillFeed(`${attacker.name} erased ${target.name}.`);
    }
  } else {
    addKillFeed(`${target.name} collapsed.`);
  }

  if (attacker && attacker.kills >= CONFIG.killLimit) {
    endMatch(attacker);
  }
}

function applyDamage(target, amount, attacker, weaponLabel, headshot = false) {
  if (!game.active || !target.alive || target.spawnShield > 0) {
    return;
  }

  target.health -= amount;

  if (target === player) {
    player.damageFlash = Math.min(0.7, player.damageFlash + 0.32);
  } else {
    target.flashTimer = 0.12;
    target.accentMaterial.emissiveIntensity = 2;
    target.accentMaterial.update();
  }

  if (target.health > 0) {
    return;
  }

  target.health = 0;
  spawnPulse(getActorChestPosition(target), headshot ? materials.accentWarm : materials.trim);
  scheduleRespawn(target, target === player ? CONFIG.playerRespawn : CONFIG.botRespawn);
  onKill(attacker, target, weaponLabel, headshot);
}

function startReload() {
  if (!player.alive) {
    return;
  }

  const weapon = WEAPONS[player.currentWeapon];
  const state = getPlayerWeaponState();
  if (player.reloadTimer > 0 || state.magazine >= weapon.magazine) {
    return;
  }
  player.reloadTimer = weapon.reload;
  player.reloadingWeapon = player.currentWeapon;
}

function finishReload() {
  const weaponId = player.reloadingWeapon || player.currentWeapon;
  const weapon = WEAPONS[weaponId];
  const state = player.inventory[weaponId];
  state.magazine = weapon.magazine;
  if (state.reserve !== Number.POSITIVE_INFINITY) {
    state.reserve = Math.max(0, state.reserve - weapon.magazine);
  }
  player.reloadingWeapon = null;
}

function switchWeapon(weaponId) {
  if (!WEAPONS[weaponId] || player.currentWeapon === weaponId) {
    return;
  }
  player.currentWeapon = weaponId;
  player.reloadTimer = 0;
  player.reloadingWeapon = null;
  player.spreadBloom *= 0.45;
  updateWeaponPresentation();
}

function firePlayerWeapon() {
  if (!game.active || !player.alive || player.reloadTimer > 0) {
    return;
  }

  const weapon = WEAPONS[player.currentWeapon];
  const state = getPlayerWeaponState();
  const triggerAllowed = weapon.auto ? input.firing : input.firing && !input.fireConsumed;

  if (!triggerAllowed || player.shotCooldown > 0) {
    return;
  }

  if (state.magazine <= 0) {
    startReload();
    input.fireConsumed = true;
    return;
  }

  state.magazine -= 1;
  player.shotCooldown = 1 / weapon.fireRate;
  player.spawnShield = 0;
  player.spreadBloom = clamp(player.spreadBloom + weapon.bloomPerShot, 0, 1.4);
  player.pitch = clamp(player.pitch - weapon.recoilPitch, -1.2, 1.15);
  player.yaw -= rand(-weapon.recoilYaw, weapon.recoilYaw);
  viewModel.kick = Math.min(0.16, viewModel.kick + 0.1);
  viewModel.flashTimer = 0.05;
  input.fireConsumed = true;

  const origin = getActorEyePosition(player);
  tempVecA.copy(player.camera.forward).normalize();

  const speedRatio = clamp(Math.hypot(player.velocityX, player.velocityZ) / CONFIG.sprintSpeed, 0, 1);
  const spread = weapon.spread + weapon.moveSpread * speedRatio + player.spreadBloom * 0.012;
  tempVecB.copy(player.camera.right).mulScalar(rand(-spread, spread));
  tempVecC.copy(player.camera.up).mulScalar(rand(-spread, spread));
  tempVecA.add(tempVecB).add(tempVecC).normalize();

  let bestDistance = weapon.range;
  let hitActor = null;
  let headshot = false;

  for (const actor of bots) {
    if (!actor.alive) {
      continue;
    }

    const headCenter = getActorEyePosition(actor);
    const headDistance = raySphereDistance(origin, tempVecA, headCenter, 0.28, bestDistance);
    if (headDistance < bestDistance) {
      bestDistance = headDistance;
      hitActor = actor;
      headshot = true;
    }

    const bodyCenter = getActorChestPosition(actor);
    const bodyDistance = raySphereDistance(origin, tempVecA, bodyCenter, 0.58, bestDistance);
    if (bodyDistance < bestDistance) {
      bestDistance = bodyDistance;
      hitActor = actor;
      headshot = false;
    }
  }

  for (const box of sightColliders) {
    const boxDistance = rayAabbDistance(origin, tempVecA, box, bestDistance);
    if (boxDistance < bestDistance) {
      bestDistance = boxDistance;
      hitActor = null;
    }
  }

  const hitPosition = new pc.Vec3(
    origin.x + tempVecA.x * bestDistance,
    origin.y + tempVecA.y * bestDistance,
    origin.z + tempVecA.z * bestDistance
  );
  spawnTracer(origin, hitPosition, weapon.color, 0.065, weapon.id === "smg" ? 0.04 : 0.05);
  spawnPulse(hitPosition, headshot ? materials.accentWarm : materials.trim, 0.12);

  if (hitActor) {
    const damage = headshot ? weapon.damage * weapon.headshot : weapon.damage;
    player.hitMarker = 0.12;
    applyDamage(hitActor, damage, player, weapon.label, headshot);
  }
}

function pickBotTarget(bot) {
  let bestTarget = null;
  let bestScore = Number.POSITIVE_INFINITY;
  const botPosition = getActorPosition(bot);
  const botEye = getActorEyePosition(bot);

  for (const actor of allActors()) {
    if (actor === bot || !actor.alive) {
      continue;
    }

    const actorPosition = getActorPosition(actor);
    const dx = actorPosition.x - botPosition.x;
    const dz = actorPosition.z - botPosition.z;
    const distance = Math.hypot(dx, dz);
    const visible = lineOfSight(botEye, getActorChestPosition(actor));
    const score = distance + (visible ? -6 : 5) + (actor === player ? -2 : 0);

    if (score < bestScore) {
      bestScore = score;
      bestTarget = actor;
    }
  }

  return bestTarget;
}

function fireBotWeapon(bot, target) {
  if (!bot.alive || !target.alive) {
    return;
  }

  const start = getActorEyePosition(bot);
  const targetPoint = Math.random() < 0.18 ? getActorEyePosition(target) : getActorChestPosition(target);
  if (!lineOfSight(start, targetPoint)) {
    return;
  }

  bot.shotCooldown = 1 / bot.weapon.fireRate;
  bot.spawnShield = 0;
  const distance = start.distance(targetPoint);
  const targetSpeed = target === player ? Math.hypot(player.velocityX, player.velocityZ) : Math.hypot(target.velocityX || 0, target.velocityZ || 0);
  const motionPenalty = targetSpeed * 0.02;
  const hitChance = clamp(bot.accuracy - distance * 0.008 - motionPenalty, 0.22, 0.92);
  const hit = Math.random() <= hitChance;
  const headshot = hit && Math.random() < 0.14 && distance < 26;

  let impactPoint;
  if (hit) {
    impactPoint = headshot ? getActorEyePosition(target) : getActorChestPosition(target);
    applyDamage(target, headshot ? bot.weapon.damage * 1.4 : bot.weapon.damage, bot, "Pulse Carbine", headshot);
  } else {
    impactPoint = new pc.Vec3(
      targetPoint.x + rand(-1.4, 1.4),
      targetPoint.y + rand(-0.7, 0.7),
      targetPoint.z + rand(-1.4, 1.4)
    );
  }

  spawnTracer(start, impactPoint, "#ff8c75", 0.08, 0.045);
  spawnPulse(impactPoint, materials.accentWarm, 0.1);
}

function updatePlayer(dt) {
  player.shotCooldown = Math.max(0, player.shotCooldown - dt);
  const wasReloading = player.reloadTimer > 0;
  player.reloadTimer = Math.max(0, player.reloadTimer - dt);
  player.spawnShield = Math.max(0, player.spawnShield - dt);
  player.spreadBloom = Math.max(0, player.spreadBloom - dt * 1.8);
  player.damageFlash = Math.max(0, player.damageFlash - dt * 1.7);
  player.hitMarker = Math.max(0, player.hitMarker - dt * 2.5);

  if (!player.alive) {
    player.respawnTimer = Math.max(0, player.respawnTimer - dt);
    if (player.respawnTimer === 0) {
      respawnActor(player);
    }
    refreshHud();
    return;
  }

  if (wasReloading && player.reloadTimer === 0) {
    finishReload();
  }

  if (document.pointerLockElement === canvas) {
    let inputX = 0;
    let inputZ = 0;
    if (app.keyboard.isPressed(pc.KEY_A)) inputX -= 1;
    if (app.keyboard.isPressed(pc.KEY_D)) inputX += 1;
    if (app.keyboard.isPressed(pc.KEY_W)) inputZ += 1;
    if (app.keyboard.isPressed(pc.KEY_S)) inputZ -= 1;

    const inputLength = Math.hypot(inputX, inputZ);
    if (inputLength > 0) {
      inputX /= inputLength;
      inputZ /= inputLength;
    }

    const speed = app.keyboard.isPressed(pc.KEY_SHIFT) ? CONFIG.sprintSpeed : CONFIG.moveSpeed;
    const facingX = -Math.sin(player.yaw);
    const facingZ = -Math.cos(player.yaw);
    const rightX = Math.cos(player.yaw);
    const rightZ = -Math.sin(player.yaw);
    const desiredX = (facingX * inputZ + rightX * inputX) * speed;
    const desiredZ = (facingZ * inputZ + rightZ * inputX) * speed;
    const accel = clamp(dt * CONFIG.acceleration, 0, 1);

    player.velocityX = lerp(player.velocityX, desiredX, accel);
    player.velocityZ = lerp(player.velocityZ, desiredZ, accel);

    const friction = Math.max(0, 1 - CONFIG.friction * dt * (inputLength === 0 ? 1 : 0.2));
    if (inputLength === 0) {
      player.velocityX *= friction;
      player.velocityZ *= friction;
    }

    moveActor(player, player.velocityX * dt, player.velocityZ * dt);
  } else {
    player.velocityX = lerp(player.velocityX, 0, clamp(dt * CONFIG.friction, 0, 1));
    player.velocityZ = lerp(player.velocityZ, 0, clamp(dt * CONFIG.friction, 0, 1));
  }

  player.entity.setEulerAngles(0, (player.yaw * 180) / Math.PI, 0);
  player.pitchPivot.setLocalEulerAngles((player.pitch * 180) / Math.PI, 0, 0);

  if (player.reloadTimer === 0 && getPlayerWeaponState().magazine < WEAPONS[player.currentWeapon].magazine && app.keyboard.wasPressed(pc.KEY_R)) {
    startReload();
  }

  if (player.reloadTimer === 0 && getPlayerWeaponState().magazine === 0 && player.shotCooldown === 0) {
    startReload();
  }

  firePlayerWeapon();
  refreshHud();
}

function updateBot(bot, dt) {
  if (!bot.alive) {
    bot.respawnTimer = Math.max(0, bot.respawnTimer - dt);
    if (bot.respawnTimer === 0) {
      respawnActor(bot);
    }
    return;
  }

  bot.shotCooldown = Math.max(0, bot.shotCooldown - dt);
  bot.thinkTimer = Math.max(0, bot.thinkTimer - dt);
  bot.strafeTimer = Math.max(0, bot.strafeTimer - dt);
  bot.flashTimer = Math.max(0, bot.flashTimer - dt);
  bot.spawnShield = Math.max(0, bot.spawnShield - dt);

  if (bot.flashTimer === 0) {
    bot.accentMaterial.emissiveIntensity = 1.2;
    bot.accentMaterial.update();
  }

  if (bot.thinkTimer === 0 || !bot.currentTarget || !bot.currentTarget.alive) {
    bot.currentTarget = pickBotTarget(bot);
    bot.thinkTimer = rand(0.18, 0.42);
  }

  if (bot.strafeTimer === 0) {
    bot.strafeDir *= -1;
    bot.strafeTimer = rand(0.8, 1.6);
  }

  const position = getActorPosition(bot);
  let moveX = 0;
  let moveZ = 0;

  if (bot.currentTarget) {
    const targetPosition = getActorPosition(bot.currentTarget);
    const dx = targetPosition.x - position.x;
    const dz = targetPosition.z - position.z;
    const distance = Math.hypot(dx, dz) || 1;
    const dirX = dx / distance;
    const dirZ = dz / distance;
    const sideX = -dirZ * bot.strafeDir;
    const sideZ = dirX * bot.strafeDir;
    const visible = lineOfSight(getActorEyePosition(bot), getActorChestPosition(bot.currentTarget));
    const desiredDistance = bot.currentTarget === player ? 11 : 9;

    if (distance > desiredDistance || !visible) {
      moveX += dirX;
      moveZ += dirZ;
    } else if (distance < 6) {
      moveX -= dirX * 0.6;
      moveZ -= dirZ * 0.6;
    }

    moveX += sideX * 0.85;
    moveZ += sideZ * 0.85;

    if (visible && distance <= bot.weapon.range && bot.shotCooldown === 0) {
      fireBotWeapon(bot, bot.currentTarget);
    }

    bot.entity.lookAt(targetPosition.x, position.y + 1.2, targetPosition.z);
    const angles = bot.entity.getEulerAngles();
    bot.entity.setEulerAngles(0, angles.y, 0);
  } else {
    const dx = bot.wanderTarget.x - position.x;
    const dz = bot.wanderTarget.z - position.z;
    const distance = Math.hypot(dx, dz);
    if (distance < 1.3) {
      bot.wanderTarget = choose(navPoints).clone();
    } else {
      moveX = dx / distance;
      moveZ = dz / distance;
      bot.entity.lookAt(bot.wanderTarget.x, position.y + 1.2, bot.wanderTarget.z);
      const angles = bot.entity.getEulerAngles();
      bot.entity.setEulerAngles(0, angles.y, 0);
    }
  }

  const moveLength = Math.hypot(moveX, moveZ);
  if (moveLength > 0) {
    moveX /= moveLength;
    moveZ /= moveLength;
  }

  bot.velocityX = lerp(bot.velocityX, moveX * 5.1, clamp(dt * 3.5, 0, 1));
  bot.velocityZ = lerp(bot.velocityZ, moveZ * 5.1, clamp(dt * 3.5, 0, 1));
  moveActor(bot, bot.velocityX * dt, bot.velocityZ * dt);
}

function updateViewModel(dt) {
  viewModel.kick = Math.max(0, viewModel.kick - dt * 6.5);
  viewModel.flashTimer = Math.max(0, viewModel.flashTimer - dt * 10);
  viewModel.muzzle.enabled = viewModel.flashTimer > 0;
  const moveAmount = clamp(Math.hypot(player.velocityX, player.velocityZ) / CONFIG.sprintSpeed, 0, 1);
  const bob = Math.sin(performance.now() * 0.012) * moveAmount * 0.018;
  viewModel.root.setLocalPosition(
    viewModel.basePosition.x,
    viewModel.basePosition.y + bob + viewModel.kick * 0.1,
    viewModel.basePosition.z + viewModel.kick * 0.12
  );
  viewModel.root.setLocalEulerAngles(viewModel.kick * 12, viewModel.kick * 6, -viewModel.kick * 8);
}

function updateEffects(dt) {
  for (let index = tracers.length - 1; index >= 0; index -= 1) {
    const tracer = tracers[index];
    tracer.life -= dt;
    if (tracer.life <= 0) {
      tracer.entity.destroy();
      tracers.splice(index, 1);
      continue;
    }
    tracer.material.opacity = tracer.life / tracer.maxLife;
    tracer.material.update();
  }

  for (let index = pulses.length - 1; index >= 0; index -= 1) {
    const pulse = pulses[index];
    pulse.life -= dt;
    if (pulse.life <= 0) {
      pulse.entity.destroy();
      pulses.splice(index, 1);
      continue;
    }
    const ratio = pulse.life / pulse.maxLife;
    const scale = 0.18 + (1 - ratio) * 0.38;
    pulse.entity.setLocalScale(scale, scale, scale);
  }
}

function updateDecor(dt) {
  const time = performance.now() * 0.001;
  for (const panel of animatedPanels) {
    if (panel.speed) {
      const angles = panel.entity.getLocalEulerAngles();
      panel.entity.setLocalEulerAngles(angles.x, angles.y + panel.speed * dt, angles.z);
    }
    if (panel.pulse !== undefined) {
      const brightness = 0.55 + Math.sin(time * 2.5 + panel.pulse) * 0.25;
      const material = panel.entity.render.meshInstances[0].material;
      material.emissiveIntensity = brightness;
      material.update();
    }
  }

  for (const ship of movingShips) {
    ship.phase += dt * ship.speed;
    const x = ship.baseX + Math.sin(ship.phase) * ship.amplitude;
    const y = ship.baseY + Math.sin(ship.phase * 1.4) * 1.2;
    const z = ship.baseZ + Math.cos(ship.phase * 0.8) * 4;
    ship.entity.setLocalPosition(x, y, z);
    ship.entity.setLocalEulerAngles(0, ship.phase * 25, 0);
  }

  game.uiRefresh -= dt;
}

function endMatch(winner = null) {
  if (game.over) {
    return;
  }

  game.active = false;
  game.over = true;
  document.exitPointerLock?.();
  ui.matchOver.classList.remove("hidden");

  const champion =
    winner ||
    allActors()
      .slice()
      .sort((left, right) => {
        if (right.kills !== left.kills) {
          return right.kills - left.kills;
        }
        return left.deaths - right.deaths;
      })[0];

  ui.winnerLine.textContent = `${champion.name} won the run`;
  ui.summaryLine.textContent =
    champion === player
      ? `You finished on top with ${player.kills} eliminations.`
      : `You finished with ${player.kills} eliminations. ${champion.name} reached ${champion.kills}.`;

  refreshHud(true);
}

function startMatch() {
  ui.startScreen.classList.add("hidden");
  ui.matchOver.classList.add("hidden");
  killFeedEntries.length = 0;
  renderKillFeed();

  game.active = true;
  game.over = false;
  game.timeRemaining = CONFIG.matchSeconds;
  game.uiRefresh = 0;

  player.kills = 0;
  player.deaths = 0;
  player.streak = 0;
  player.damageFlash = 0;
  player.hitMarker = 0;
  player.currentWeapon = "rifle";
  resetPlayerInventory();
  respawnActor(player, true);

  bots.forEach((bot) => {
    bot.kills = 0;
    bot.deaths = 0;
    bot.streak = 0;
    bot.currentTarget = null;
    bot.respawnTimer = rand(0.25, 1.3);
    bot.entity.enabled = false;
    bot.alive = false;
    bot.accentMaterial.emissiveIntensity = 1.2;
    bot.accentMaterial.update();
  });

  refreshHud(true);
}

document.addEventListener("mousemove", (event) => {
  if (!game.active || !player.alive || document.pointerLockElement !== canvas) {
    return;
  }
  player.yaw -= event.movementX * CONFIG.mouseSensitivity;
  player.pitch = clamp(player.pitch - event.movementY * CONFIG.mouseSensitivity, -1.18, 1.08);
});

canvas.addEventListener("mousedown", (event) => {
  if (event.button === 0) {
    input.firing = true;
    if (game.active && document.pointerLockElement !== canvas) {
      canvas.requestPointerLock();
    }
  }
});

window.addEventListener("mouseup", (event) => {
  if (event.button === 0) {
    input.firing = false;
    input.fireConsumed = false;
  }
});

canvas.addEventListener("click", () => {
  if (game.active && !game.over && document.pointerLockElement !== canvas) {
    canvas.requestPointerLock();
  }
});

document.addEventListener("pointerlockchange", () => {
  updateBanner();
});

window.addEventListener("keydown", (event) => {
  if (event.repeat) {
    return;
  }

  if (event.key === "1") {
    switchWeapon("pistol");
  } else if (event.key === "2") {
    switchWeapon("smg");
  } else if (event.key === "3") {
    switchWeapon("rifle");
  } else if (event.key.toLowerCase() === "r") {
    startReload();
  } else if (event.key === "Enter" && game.over) {
    startMatch();
    canvas.requestPointerLock();
  }
});

ui.startButton.addEventListener("click", () => {
  startMatch();
  canvas.requestPointerLock();
});

ui.restartButton.addEventListener("click", () => {
  startMatch();
  canvas.requestPointerLock();
});

updateWeaponPresentation();
refreshHud(true);

app.on("update", (dt) => {
  updateDecor(dt);

  if (!game.active) {
    updateViewModel(dt);
    updateEffects(dt);
    refreshHud();
    return;
  }

  game.timeRemaining = Math.max(0, game.timeRemaining - dt);
  if (game.timeRemaining === 0) {
    endMatch();
  }

  updatePlayer(dt);
  bots.forEach((bot) => updateBot(bot, dt));
  updateViewModel(dt);
  updateEffects(dt);

  for (let index = killFeedEntries.length - 1; index >= 0; index -= 1) {
    killFeedEntries[index].time -= dt;
    if (killFeedEntries[index].time <= 0) {
      killFeedEntries.splice(index, 1);
      renderKillFeed();
    }
  }
});
