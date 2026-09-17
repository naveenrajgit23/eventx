import {describe,it,expect} from 'vitest';
import {minutesToSeconds,secondsToDisplayTime,calculateRoboRaceScore,calculateDroneRaceScore} from '../scoring.js';

describe('competition time',()=>{
  it('parses minutes.seconds',()=>{
    expect(minutesToSeconds('3.56')).toBe(236);
    expect(minutesToSeconds('5.00')).toBe(300);
  });
  it('formats seconds',()=>{
    expect(secondsToDisplayTime(264)).toBe('4.24 min');
    expect(secondsToDisplayTime(314)).toBe('5.14 min');
  });
  it('rejects invalid seconds',()=>expect(()=>minutesToSeconds('3.60')).toThrow());
});

describe('scores',()=>{
  it('calculates Robo Race example',()=>
    expect(calculateRoboRaceScore({total_time:'3.56',line_touch:5,hand_touch:1,bot_exit:1,obstacle_skip:1}).finalScoreSeconds).toBe(264)
  );
  it('calculates Drone Race example',()=>
    expect(calculateDroneRaceScore({total_time:'5.00',ground_touch:2,obstacle_hit:1,obstacle_miss:1,perfect_landing:1}).finalScoreSeconds).toBe(314)
  );
});
