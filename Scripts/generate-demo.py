#!/usr/bin/env python3
"""Compose tiny original demo loops. No third-party recordings or downloads."""
from pathlib import Path
import math,struct,wave
root=Path(__file__).resolve().parents[1]/'Resources/Demo'
root.mkdir(parents=True,exist_ok=True)
for name,notes in [('demo-warmup',[220,261.63,329.63,293.66,261.63,196,220,164.81]),('demo-easy',[261.63,329.63,392,329.63,293.66,349.23,440,349.23]),('demo-homeward',[196,246.94,293.66,369.99,329.63,293.66,246.94,196])]:
 rate=22050;duration=20;data=bytearray()
 for i in range(rate*duration):
  t=i/rate;beat=t%0.5;freq=notes[int(t/0.5)%len(notes)]
  envelope=min(1,beat/0.015)*math.exp(-beat*5)
  lead=math.sin(2*math.pi*freq*t)*envelope
  bass=math.sin(2*math.pi*(freq/2)*t)*0.35*math.exp(-(t%2)*2)
  fade=min(1,t/0.2,(duration-t)/0.5)
  value=max(-1,min(1,(lead*0.25+bass*0.22)*fade))
  data+=struct.pack('<h',round(value*32767))
 with wave.open(str(root/(name+'.wav')),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate);f.writeframes(data)
print('Generated three original 20-second demo compositions')
