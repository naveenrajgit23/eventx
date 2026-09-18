export function minutesToSeconds(value){const raw=String(value??'').trim();if(!/^\d+(?:\.\d{0,2})?$/.test(raw))throw new Error('Enter time as minutes.seconds, for example 3.56.');const [minutes,seconds='0']=raw.split('.');const sec=Number(seconds.padEnd(2,'0'));if(sec>59)throw new Error('Seconds must be between 00 and 59.');return Number(minutes)*60+sec}
export function secondsToDisplayTime(value){if(value==null||value===''||isNaN(value))return 'â€”';const total=Math.max(0,Math.round(Number(value)||0));return `${Math.floor(total/60)}.${String(total%60).padStart(2,'0')} min`}
export function secondsToInputValue(value){if(value==null||value===''||isNaN(value))return '';const total=Math.max(0,Math.round(Number(value)||0));return `${Math.floor(total/60)}.${String(total%60).padStart(2,'0')}`}
export const secondsToMinutes=secondsToDisplayTime
export function calculateScore(totalTimeSeconds,rules,values={}){if(totalTimeSeconds<0)throw new Error('Time must be zero or greater.');let final=totalTimeSeconds;const details=rules.map(rule=>{const quantity=Number(values[rule.key]??0);if(!Number.isFinite(quantity)||quantity<0)throw new Error('All quantities must be zero or greater.');const calculatedSeconds=quantity*rule.seconds;final+=rule.operation==='add'?calculatedSeconds:-calculatedSeconds;return{...rule,quantity,calculatedSeconds}});return{totalTimeSeconds,finalScoreSeconds:Math.max(0,Math.round(final)),details}}
export const ROBO_RULES=[{key:'line_touch',name:'Line Touch',seconds:2,operation:'add'},{key:'out_of_line',name:'Out of Line',seconds:5,operation:'add'},{key:'completely_bot_exit',name:'Complete Bot Exit',seconds:20,operation:'add'},{key:'hand_touch',name:'Hand Touch',seconds:10,operation:'add'},{key:'obstacle_skip',name:'Obstacle Skip',seconds:25,operation:'add'}]
export const DRONE_RULES=[
  {key:'ground_touch',name:'Ground Touch',seconds:5,operation:'add'},
  {key:'obstacle_hit',name:'Obstacle Hit',seconds:4,operation:'add'},
  {key:'obstacle_miss',name:'Obstacle Miss',seconds:8,operation:'add'},
  {key:'hand_touch',name:'Hand Touch',seconds:5,operation:'add'},
  {key:'landing_miss',name:'Landing Miss',seconds:5,operation:'add'}
]
export const calculateRoboRaceScore=data=>calculateScore(minutesToSeconds(data.total_time),ROBO_RULES,data)
export const calculateDroneRaceScore=data=>calculateScore(minutesToSeconds(data.total_time),DRONE_RULES,data)
export const calculateFinalResult=(round1,round2)=>Number(round1||0)+Number(round2||0)
export function calculateLeaderboard(rows,scoreKey='final_score_seconds'){return [...rows].sort((a,b)=>(a[scoreKey]-b[scoreKey])||((a.round_2_score??Infinity)-(b.round_2_score??Infinity))||((a.round_1_score??Infinity)-(b.round_1_score??Infinity))||a.team_code.localeCompare(b.team_code)).map((row,index)=>({...row,rank:index+1}))}
