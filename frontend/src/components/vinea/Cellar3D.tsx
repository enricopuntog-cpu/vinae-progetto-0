import { Suspense, useEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame, type ThreeEvent } from "@react-three/fiber";
import { OrbitControls, Text, Html } from "@react-three/drei";
import type * as THREE from "three";
import type { CellarBottle, StorageEnvironment, StorageModule, StorageSlot } from "@/data/cellar";
import type { Wine } from "@/data/wines";

type Props = {
  environments: StorageEnvironment[];
  modules: StorageModule[];
  slots: StorageSlot[];
  bottiglie: CellarBottle[];
  wines: Wine[];
  activeEnvId: string;
  onSelectSlot: (slot: StorageSlot | null) => void;
  highlightedSlotId?: string;
  reduceMotion?: boolean;
};

const TIPO_COLOR: Record<string, string> = {
  Rosso: "#6B2138",
  Bianco: "#E8DEB8",
  Bollicine: "#B59A63",
  Rosato: "#C48A9A",
  Dolce: "#7B4E2A",
};

/** Pausa il rendering 3D quando il canvas non è in viewport, per risparmiare GPU. */
function useOnScreen<T extends Element>(
  rootMargin = "120px",
): [React.RefObject<T | null>, boolean] {
  const ref = useRef<T | null>(null);
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    if (typeof IntersectionObserver === "undefined" || !ref.current) return;
    const el = ref.current;
    const obs = new IntersectionObserver(
      (entries) => {
        for (const e of entries) setVisible(e.isIntersecting);
      },
      { root: null, rootMargin, threshold: 0 },
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, [rootMargin]);
  return [ref, visible];
}

export default function Cellar3D({
  modules,
  slots,
  bottiglie,
  wines,
  activeEnvId,
  onSelectSlot,
  highlightedSlotId,
  reduceMotion,
}: Props) {
  const envModules = modules.filter((m) => m.environmentId === activeEnvId);
  const bottleById = useMemo(() => new Map(bottiglie.map((b) => [b.bottleId, b])), [bottiglie]);
  const wineById = useMemo(() => new Map(wines.map((w) => [w.id, w])), [wines]);
  const [wrapperRef, onScreen] = useOnScreen<HTMLDivElement>("160px");

  const shouldAutoRotate = !reduceMotion && onScreen;
  // "demand": si aggiorna solo su interazione. "always": rendering continuo (necessario per autoRotate).
  const frameloop: "always" | "demand" = shouldAutoRotate ? "always" : "demand";

  return (
    <div ref={wrapperRef} className="h-full w-full">
      <Canvas
        shadows={false}
        dpr={[1, 1.25]}
        camera={{ position: [0, 2.2, 5.5], fov: 45 }}
        gl={{ antialias: false, powerPreference: "high-performance", stencil: false, depth: true }}
        frameloop={frameloop}
        onPointerMissed={() => onSelectSlot(null)}
      >
        <color attach="background" args={["#1a1512"]} />
        <ambientLight intensity={0.55} />
        <directionalLight position={[4, 6, 4]} intensity={0.9} />
        <pointLight position={[-3, 3, 2]} intensity={0.4} color="#B59A63" />

        {/* Pavimento */}
        <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -0.02, 0]}>
          <planeGeometry args={[20, 12]} />
          <meshStandardMaterial color="#2a201a" />
        </mesh>

        <Suspense fallback={null}>
          {envModules.map((m) => (
            <ModuleMesh
              key={m.id}
              mod={m}
              slots={slots.filter((s) => s.moduleId === m.id)}
              bottleById={bottleById}
              wineById={wineById}
              highlightedSlotId={highlightedSlotId}
              onSelectSlot={onSelectSlot}
            />
          ))}
        </Suspense>

        <OrbitControls
          enablePan
          enableZoom
          enableRotate
          autoRotate={shouldAutoRotate}
          autoRotateSpeed={0.6}
          minDistance={2}
          maxDistance={12}
          maxPolarAngle={Math.PI / 2.1}
        />
      </Canvas>
    </div>
  );
}

function ModuleMesh({
  mod,
  slots,
  bottleById,
  wineById,
  highlightedSlotId,
  onSelectSlot,
}: {
  mod: StorageModule;
  slots: StorageSlot[];
  bottleById: Map<string, CellarBottle>;
  wineById: Map<string, Wine>;
  highlightedSlotId?: string;
  onSelectSlot: (s: StorageSlot) => void;
}) {
  const w = mod.columns * 0.24 + 0.15;
  const h = mod.rows * 0.32 + 0.15;
  const d = 0.35;

  return (
    <group position={mod.position} rotation={[0, mod.rotationY ?? 0, 0]}>
      {/* Struttura scaffale */}
      <mesh position={[0, h / 2, -d / 2]}>
        <boxGeometry args={[w, h, 0.04]} />
        <meshStandardMaterial color="#3a2a1e" />
      </mesh>
      {[...Array(mod.rows + 1)].map((_, i) => (
        <mesh key={`row-${i}`} position={[0, i * 0.32 + 0.075, 0]}>
          <boxGeometry args={[w, 0.02, d]} />
          <meshStandardMaterial color="#4a3427" />
        </mesh>
      ))}
      {/* Bottiglie */}
      {slots.map((s) => {
        const bottle = s.bottleId ? bottleById.get(s.bottleId) : undefined;
        const wine = bottle ? wineById.get(bottle.wineVintageId) : undefined;
        const color = wine ? (TIPO_COLOR[wine.tipo] ?? "#6B2138") : "#333";
        const x = -w / 2 + 0.12 + s.column * 0.24;
        const y = s.row * 0.32 + 0.28;
        const highlighted = s.id === highlightedSlotId;
        return (
          <group key={s.id} position={[x, y, 0]}>
            {bottle && (
              <mesh
                castShadow={false}
                onClick={(e: ThreeEvent<MouseEvent>) => {
                  e.stopPropagation();
                  onSelectSlot(s);
                }}
              >
                <cylinderGeometry args={[0.05, 0.05, 0.24, 10]} />
                <meshStandardMaterial color={color} roughness={0.4} metalness={0.1} />
              </mesh>
            )}
            {!bottle && (
              <mesh
                onClick={(e: ThreeEvent<MouseEvent>) => {
                  e.stopPropagation();
                  onSelectSlot(s);
                }}
              >
                <boxGeometry args={[0.14, 0.02, 0.14]} />
                <meshStandardMaterial color="#2a1f18" transparent opacity={0.6} />
              </mesh>
            )}
            {highlighted && <HighlightRing wine={wine} />}
          </group>
        );
      })}
      {/* Label modulo */}
      <Text
        position={[0, -0.1, 0.2]}
        fontSize={0.09}
        color="#F7F3EC"
        anchorX="center"
        anchorY="top"
      >
        {mod.label}
      </Text>
    </group>
  );
}

function HighlightRing({ wine }: { wine?: Wine }) {
  const ref = useRef<THREE.Mesh>(null);
  useFrame(({ clock }) => {
    if (ref.current) {
      const s = 1 + Math.sin(clock.elapsedTime * 3) * 0.15;
      ref.current.scale.set(s, 1, s);
    }
  });
  return (
    <>
      <mesh ref={ref} position={[0, -0.11, 0]} rotation={[-Math.PI / 2, 0, 0]}>
        <ringGeometry args={[0.09, 0.13, 24]} />
        <meshBasicMaterial color="#B59A63" transparent opacity={0.9} />
      </mesh>
      {wine && (
        <Html position={[0, 0.22, 0]} center distanceFactor={6}>
          <div className="pointer-events-none whitespace-nowrap rounded-md bg-bordeaux px-2 py-1 text-[10px] font-semibold text-crema shadow-lg">
            {wine.nome} {wine.annata}
          </div>
        </Html>
      )}
    </>
  );
}

/** Lazy loader gate + WebGL fallback */
export function useHasWebGL() {
  const [ok, setOk] = useState<boolean | null>(null);
  useEffect(() => {
    try {
      const c = document.createElement("canvas");
      const gl = c.getContext("webgl2") || c.getContext("webgl");
      setOk(!!gl);
    } catch {
      setOk(false);
    }
  }, []);
  return ok;
}
