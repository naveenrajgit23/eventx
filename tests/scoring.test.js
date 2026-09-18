import {describe,it,expect} from 'vitest';
import {minutesToSeconds,secondsToDisplayTime,calculateRoboRaceScore,calculateDroneRaceScore} from '../scoring.js';

describe('competition time',()=>{
  it('parses minutes.seconds',()=>{
    expect(minutesToSeconds('3.56')).toBe(236);
    expect(minutesToSeconds('5.00')).toBe(300);
  });
  it('formats seconds',()=>{
    expect(secondsToDisplayTime(264)).toBe('4.24 min');
    expect(secondsToDisplayTime(311)).toBe('5.11 min');
  });
  it('rejects invalid seconds',()=>expect(()=>minutesToSeconds('3.60')).toThrow());
});

// ---------------------------------------------------------------------------
// Robo Race scoring
// New formula:
//   Final = Total + (Line Touch x 2) + (Out of Line x 5)
//         + (Complete Bot Exit x 20) + (Hand Touch x 10) + (Obstacle Skip x 25)
// ---------------------------------------------------------------------------
describe('Robo Race scores',()=>{

  // Required test case:
  // 236 + (5x2) + (2x5) + (1x20) + (1x10) + (1x25) = 311 => 5.11 min
  it('calculates full penalty example (311 s)',()=>{
    const result=calculateRoboRaceScore({
      total_time:'3.56',
      line_touch:5,
      out_of_line:2,
      completely_bot_exit:1,
      hand_touch:1,
      obstacle_skip:1
    });
    expect(result.finalScoreSeconds).toBe(311);
    expect(secondsToDisplayTime(result.finalScoreSeconds)).toBe('5.11 min');
  });

  // Zero penalties: total time is returned unchanged
  it('returns total time when all penalties are zero',()=>{
    const result=calculateRoboRaceScore({
      total_time:'3.56',
      line_touch:0,
      out_of_line:0,
      completely_bot_exit:0,
      hand_touch:0,
      obstacle_skip:0
    });
    expect(result.finalScoreSeconds).toBe(236);
  });

  // Individual rule: Line Touch (+2 s each)
  it('applies Line Touch penalty (+2 s each)',()=>{
    const result=calculateRoboRaceScore({total_time:'3.56',line_touch:3});
    expect(result.finalScoreSeconds).toBe(236+3*2); // 242
  });

  // Individual rule: Out of Line (+5 s per wheel)
  it('applies Out of Line penalty (+5 s per wheel)',()=>{
    const result=calculateRoboRaceScore({total_time:'3.56',out_of_line:4});
    expect(result.finalScoreSeconds).toBe(236+4*5); // 256
  });

  // Individual rule: Complete Bot Exit (+20 s each)
  it('applies Complete Bot Exit penalty (+20 s each)',()=>{
    const result=calculateRoboRaceScore({total_time:'3.56',completely_bot_exit:2});
    expect(result.finalScoreSeconds).toBe(236+2*20); // 276
  });

  // Individual rule: Hand Touch (+10 s each)
  it('applies Hand Touch penalty (+10 s each)',()=>{
    const result=calculateRoboRaceScore({total_time:'3.56',hand_touch:3});
    expect(result.finalScoreSeconds).toBe(236+3*10); // 266
  });

  // Individual rule: Obstacle Skip (+25 s each)
  it('applies Obstacle Skip penalty (+25 s each)',()=>{
    const result=calculateRoboRaceScore({total_time:'3.56',obstacle_skip:2});
    expect(result.finalScoreSeconds).toBe(236+2*25); // 286
  });
});

// ---------------------------------------------------------------------------
// Drone Race scoring — must be UNCHANGED
// ---------------------------------------------------------------------------
describe('Drone Race scores',()=>{
  it('calculates Drone Race example',()=>
    expect(calculateDroneRaceScore({total_time:'5.00',ground_touch:2,obstacle_hit:1,obstacle_miss:1,perfect_landing:1}).finalScoreSeconds).toBe(314)
  );
});