UIDS = [
"08jorchkq6b0","bvef7ftw2gdq2","bqeiiptlioatg","c4qyito1l113f","dg028li7cwtcg",
"bvnjl8ga7iel6","c4n4mfagj0x02","f7cwkm24xdoc","bir1kwfkl1rrf","tuyam6pmi3e6",
"imm65hgolsdp","wcob7buq1aon","paa5fmbhmq73","cf675ca8wlc81","dr3kfbsck580y",
"bse5fq0g7xuax","hf842pcx768b","hnn7o7kdkl2t","b5u53vmbpyrht","crfi3vw0kjf5a",
"ml5rf0l13qvm","befef6k4srmei","be21sc0o5qayq","cajbd5itvjmfq","dlqxxgtavsmr3",
"niahwy7kgcmk","btm4ffwvqx6q3","hfadl3lmd0n1","b5cfq7k5qns3","ckkxrkyxsah5h",
"cgko1c1pkocig"
]
out = "D:/武侠游戏/assets/characters/matte/matte_idle.tres"
uid_lines = []
frames_entries = []
for i in range(1, 32):
    n = "%05d" % i
    png = "res://assets/characters/matte/matte_%s.png" % n
    rid = str(i)
    uid_lines.append('[ext_resource type="Texture2D" uid="uid://%s" path="%s" id="%s"]' % (UIDS[i-1], png, rid))
    frames_entries.append('{"duration":0.08,"texture":"%s"}' % png)
sf_uid = "uid://matteidle0001"
header = '[gd_resource type="SpriteFrames" load_steps=%d format=3 uid="%s"]\n\n' % (32, sf_uid)
exts = "\n".join(uid_lines)
anim = ('\n[resource]\nanimations=[\n{\n"frames":[\n' + ",\n".join(frames_entries) + "\n],\n"
        '"loop":true,\n"name":"idle",\n"speed":12.0\n}\n]\n')
with open(out, "w", encoding="utf-8") as f:
    f.write(header)
    f.write(exts)
    f.write(anim)
print("written", out, "bytes", __import__("os").path.getsize(out))
