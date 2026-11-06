ขั้นตอนตั้งค่า

1.  ติดตั้ง Jenkins บน host (jenkins/)

- สร้าง jenkins/.env ใส่ DOCKER_GID=$(getent group docker | cut -d: -f3)
  - ไม่ใส่ docker compose จะ fail ทันทีเพราะ ${DOCKER_GID:?...}
- รัน docker compose up -d --build
- image ใช้ base jenkins:lts-jdk21 และเพิ่ม docker-ce-cli, buildx, compose plugin, ssh client
- plugin ที่ลงเพิ่ม: gitlab, ssh-agent, git, workflow-aggregator, credentials-binding, timestamper
- Jenkins ใช้ Docker daemon ของ host ผ่าน docker.sock ไม่ใช่ DinD
- port เปิดแค่ 127.0.0.1:8080 ต้องมี reverse proxy (nginx/caddy) พร้อม TLS ไว้ให้ GitLab ยิง webhook เข้ามา
- เปิด Jenkins ครั้งแรก: อ่าน initial password จาก docker logs jenkins

2.  สร้าง Credentials ใน Jenkins (ID ต้องตรงกับใน Jenkinsfile)

┌───────────────────┬────────────────────────────────────────────────────────────────────────────────┬────────────────┐
│ ID │ ชนิด │ ใช้ใน stage │
├───────────────────┼────────────────────────────────────────────────────────────────────────────────┼────────────────┤
│ gitlab-registry │ Username + Password (deploy token หรือ PAT ที่มี read_registry และ write_registry) │ Registry login │
├───────────────────┼────────────────────────────────────────────────────────────────────────────────┼────────────────┤
│ deploy-server-ssh │ SSH private key │ Deploy │
└───────────────────┴────────────────────────────────────────────────────────────────────────────────┴────────────────┘

อาจต้องมี credential สําหรับ clone repo GitLab เพิ่มด้วย

3.  เตรียม server ปลายทาง

- วาง server/deploy.sh ที่ /opt/mattersolv/deploy.sh แล้ว chmod +x
- มี /opt/mattersolv/docker-compose.yml และ .env
- service ชื่อ frontend ใน compose ต้องใช้ image: ...mattersolv_frontend:${FRONTEND_TAG}
- user deploy ต้องอยู่ในกลุ่ม docker
- ใส่ public key ของ deploy-server-ssh ใน authorized_keys
- server ต้อง docker login registry.gitlab.com ไว้แล้ว เพราะ deploy.sh ทํา docker compose pull เอง

4.  สร้าง Job ใน Jenkins

- ชนิด Pipeline เลือก "Pipeline script from SCM" ชี้ที่ repo frontend, branch develop, Script Path Jenkinsfile
- ต้องชี้ repo frontend เพราะ stage Build ใช้ ./scripts/build-and-push-image.sh ซึ่งอยู่ใน workspace ของ repo นั้น frontend/Jenkinsfile ใน repo
  นี้จึงเป็นแค่ต้นฉบับที่ต้อง copy ไป
- Build Triggers: "Build when a change is pushed to GitLab" และกรอง branch เป็น develop
- ใน GitLab: Settings → Webhooks ใส่ URL https://<jenkins>/project/<job> และ secret token

5.  แก้ค่า TODO ใน Jenkinsfile

- NEXT_PUBLIC_API_BASE_URL เป็น https://api-dev.example.com/api ซึ่งยังเป็น placeholder ค่านี้ถูกฝังใน bundle ตอน build ต้องแก้ก่อน build ครั้งแรก
- DEPLOY_HOST เป็น deploy@YOUR_SERVER_IP ซึ่งยังเป็น placeholder เช่นกัน

6.  Stage ใน pipeline

- Prepare: TAG = git rev-parse --short=12 HEAD และตั้งชื่อ build เป็น #N <tag>
- Registry login: docker login --password-stdin จึงไม่รั่วใน log
- Build & Push: เรียกสคริปต์ของ repo โดยอ่าน IMAGE, PLATFORMS, NEXT*PUBLIC*\*, SKIP_DOCKER_LOGIN=1 จาก env
- Deploy: ssh deploy@host deploy.sh FRONTEND_TAG <tag> frontend
- deploy.sh ตรวจ argument ด้วย regex ล็อกด้วย flock ทํา backup .env แล้ว pull และ up ถ้า fail จะ rollback .env กลับ
- post: prune build cache ที่เก่ากว่า 7 วัน

---

gitlab repo token
สรุป: ต้องเพิ่ม ถ้า repo frontend เป็น private ซึ่งน่าจะใช่ เพราะอยู่ใน group alt-pro-tech บน GitLab ถ้าเป็น public ไม่ต้องเพิ่ม ผมไม่ได้ตรวจว่า repo ตั้งเป็นแบบไหน

ทําไมต้องมี

- Job แบบ "Pipeline script from SCM" ให้ Jenkins clone repo เองก่อนอ่าน Jenkinsfile
- credential นี้ใช้ตั้งในหน้า job ส่วน SCM ไม่ได้อ้างอิงใน Jenkinsfile
- gitlab-registry ใช้แทนไม่ได้ ถ้าเป็น deploy token ที่มีแค่ read_registry และ write_registry ซึ่ง clone ไม่ได้

วิธีเลือก (เลือกอย่างเดียว)

┌───────────────────────────────────┬───────────────────────────────┬─────────────────────────────────────────────────────────────────────────────┐
│ URL ของ repo │ Credential │ ตั้งค่า │
├───────────────────────────────────┼───────────────────────────────┼─────────────────────────────────────────────────────────────────────────────┤
│ HTTPS (https://gitlab.com/...git) │ Username with password │ GitLab deploy token ที่มี scope read_repository อย่างเดียว ใช้ ID เช่น gitlab-repo │
├───────────────────────────────────┼───────────────────────────────┼─────────────────────────────────────────────────────────────────────────────┤
│ SSH (git@gitlab.com:...git) │ SSH Username with private key │ deploy key ของ repo (read-only) แยกจาก deploy-server-ssh │
└───────────────────────────────────┴───────────────────────────────┴─────────────────────────────────────────────────────────────────────────────┘

แนะนํา HTTPS กับ deploy token ตั้งง่ายกว่า และสิทธิ์จํากัดแค่อ่าน repo

ขั้นตอน (HTTPS)

1.  GitLab → repo frontend → Settings → Repository → Deploy tokens → สร้าง token ติ๊ก read_repository เท่านั้น เก็บ username และ token ไว้
2.  Jenkins → Credentials → Global → Add → Kind: Username with password, ID: gitlab-repo
3.  ตั้งค่า job → Pipeline → Definition: Pipeline script from SCM → SCM: Git → Repository URL → Credentials: เลือก gitlab-repo → Branch: \*/develop →
    Script Path: Jenkinsfile

ถ้าใช้ SSH Jenkins ต้องเชื่อถือ host key ของ gitlab.com ด้วย ตั้งที่ Manage Jenkins → Security → Git Host Key Verification Configuration หรือใส่ใน known_hosts ของ
container

หมายเหตุ

- ถ้าจะใช้ backend ด้วย ทํา credential แยก หรือใช้ group deploy token ตัวเดียว สิทธิ์ read_repository ครอบ repo ใน group
- Webhook จาก GitLab ไม่ต้องใช้ credential นี้ ใช้ secret token ที่ตั้งตอนสร้าง webhook

ขั้นตอนนี้ให้ Jenkins ใช้ SSH key เข้าไปสั่ง deploy.sh บน server ได้โดยไม่ต้องใช้รหัสผ่าน

1.  สร้าง key pair บนเครื่องคุณ (ไม่ใช่บน Jenkins)

```bash
ssh-keygen -t ed25519 -C "jenkins-deploy" -f ./deploy-server-ssh -N ""
```

ได้ 2 ไฟล์:

- deploy-server-ssh คือ private key ไว้ใส่ใน Jenkins
- deploy-server-ssh.pub คือ public key ไว้ใส่บน server

2.  ใส่ public key บน server

```bash
ssh-copy-id -i deploy-server-ssh.pub deploy@<SERVER_IP>
```

หรือเพิ่มเองใน ~deploy/.ssh/authorized_keys โดยตั้ง permission ให้ถูก:

```bash
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
```

ถ้า permission หลวม sshd จะไม่ยอมรับ key

3.  เพิ่ม Credential ใน Jenkins

- Manage Jenkins → Credentials → System → Global credentials → Add Credentials
- Kind: SSH Username with private key (ไม่ใช่ Username with password)
- ID: deploy-server-ssh ต้องตรงตัวอักษรกับใน Jenkinsfile
- Username: deploy
- Private Key: เลือก "Enter directly" แล้ววางเนื้อหาทั้งไฟล์ deploy-server-ssh รวมบรรทัด -----BEGIN ... ----- และ -----END ... -----
- หลังบันทึก ลบไฟล์ private key บนเครื่องคุณทิ้ง

4.  Jenkinsfile ใช้อย่างไร

```groovy
sshagent(credentials: ['deploy-server-ssh']) {
 sh 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$DEPLOY_HOST" ...'
}
```

- plugin ssh-agent เปิด ssh-agent ชั่วคราวระหว่าง build และโหลด key เข้าไป
- คําสั่ง ssh ในบล็อกนั้นใช้ key ผ่าน agent เอง ไม่มีไฟล์ key ในโฟลเดอร์ workspace
- ผู้ใช้ที่เชื่อมต่อมาจาก DEPLOY_HOST (deploy@...) ไม่ใช่ช่อง Username ในหน้า credential
- build ครั้งแรก accept-new จะบันทึก host key ของ server ลง /var/jenkins_home/.ssh/known_hosts

5.  ทดสอบก่อนรัน pipeline

```bash
ssh -i ./deploy-server-ssh deploy@<SERVER_IP> "echo ok"
```

ต้องได้ ok โดยไม่ถามรหัสผ่าน และ user deploy ต้องอยู่ในกลุ่ม docker กับรัน /opt/mattersolv/deploy.sh ได้

ข้อควรระวัง

- key นี้เปิดทางเข้า server ได้เท่าสิทธิ์ของ user deploy ใครแก้ Jenkinsfile หรือ job ก็ใช้ key นี้ได้
- ทางเสริมความปลอดภัย: ใน authorized_keys ใส่ option นําหน้า key เช่น from="<IP ของ Jenkins>",no-port-forwarding,no-agent-forwarding,no-pty
- ถ้า key หลุดหรือเปลี่ยนคน ให้สร้างคู่ใหม่ แล้วเปลี่ยนทั้งบน server และใน Jenkins credential
- frontend กับ backend ใช้ credential ID นี้ร่วมกัน
