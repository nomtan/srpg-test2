import { AnimationMixer, LoopOnce, LoopRepeat, type AnimationClip, type Object3D } from "three";

export interface AnimationSettings { clip: string | null; playing: boolean; speed: number; loop: boolean; revision: number }
export class AnimationController {
  readonly mixer: AnimationMixer;
  constructor(private readonly root: Object3D, private readonly clips: AnimationClip[]) { this.mixer = new AnimationMixer(root); }
  configure(settings: AnimationSettings): string[] {
    this.mixer.stopAllAction(); // Restore rest values, including tracks absent in the next clip.
    if (!settings.playing || !settings.clip) return [];
    const clip = this.clips.find((c) => c.name === settings.clip);
    if (!clip) return [`Animation Clipがありません: ${settings.clip}`];
    const action = this.mixer.clipAction(clip);
    action.reset().setLoop(settings.loop ? LoopRepeat : LoopOnce, settings.loop ? Infinity : 1);
    action.clampWhenFinished = !settings.loop;
    action.setEffectiveTimeScale(Number.isFinite(settings.speed) ? Math.max(0.25, Math.min(2, settings.speed)) : 1);
    action.play();
    this.mixer.update(0);
    return [];
  }
  update(delta: number) { this.mixer.update(delta); }
  dispose() { this.mixer.stopAllAction(); this.mixer.uncacheRoot(this.root); }
}
