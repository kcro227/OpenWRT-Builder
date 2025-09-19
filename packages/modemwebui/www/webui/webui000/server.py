g='MODE'
f=KeyboardInterrupt
m=isinstance
U=True
e='direct'
d='tom_modem'
T='HOST'
R='SERIAL'
Y=None
O='HTTP'
X=b''
W='OK'
N='WEBSOCKET'
S=range
Q=str
J=len
E='PORT'
L=print
K=Exception
I='ignore'
H=False
import asyncio as C,websockets as h,json as F,os as D,sys,threading as i,http.server,socketserver as j,subprocess as n,logging as A,glob,serial as b,binascii as p,re
A.basicConfig(level=A.INFO,format='%(asctime)s %(levelname)s %(message)s')
A.getLogger().setLevel(A.ERROR)
P=D.path.join(D.path.dirname(D.path.abspath(__file__)),'config.json')
def o():
	J='utf-8';B={N:{T:'0.0.0.0',E:8765},O:{E:8001},R:{E:'/dev/ttyUSB0',g:d}}
	if not D.path.exists(P):
		with open(P,'w',encoding=J)as G:F.dump(B,G,indent=4,ensure_ascii=H)
		return B
	with open(P,'r',encoding=J)as G:C=F.load(G)
	for A in B:
		if A not in C:C[A]=B[A]
		else:
			for I in B[A]:
				if I not in C[A]:C[A][I]=B[A][I]
	return C
B=o()
c=B[R][g]
V=B[R][E]
G=Y
def q():
	D='AT';import time,serial.tools.list_ports;E=[A.device for A in serial.tools.list_ports.comports()]
	for B in E:
		try:
			if c==e:
				C=serial.Serial(B,115200,timeout=2);C.reset_input_buffer();C.write(b'AT\r');time.sleep(.5);F=C.read_all().decode(errors=I);C.close()
				if D in F:A.info(f"[direct模式] 检测到AT端口: {B}");return B
			else:
				G=n.run([d,B,'-c',D],capture_output=U,timeout=2);H=G.stdout.decode(errors=I)
				if D in H:A.info(f"检测到AT端口: {B}");return B
		except K as J:A.info(f"检测端口{B}失败: {J}");continue
if V=='auto':G=q()
else:G=V
if not G:L('未检测到AT端口，程序退出');sys.exit(1)
k=set()
l=C.Lock()
async def r(args):
	o='串口异常';n='+CMS ERROR:';m='短信发送成功';k='+CMGS:';j=b'\x1a';i='收到 > 提示符，准备发送PDU数据';h='AT+CMGF=0 未返回OK';g='发送: AT+CMGF=0';f=b'AT+CMGF=0\r';d='\\D';O='未收到 > 提示符，模块无响应';N=args;import re
	if J(N)<3:A.error('参数不足，格式应为 SEND_SMS,短信中心号码手机号,"短信内容"');return'参数不足，格式应为 SEND_SMS,手机号,"短信内容"'
	q=N[1].strip();R=N[2].strip();T=N[3].strip('"');A.info(f"准备发送短信: 手机号={R}, 内容={T}")
	def U(number):
		A=number;A=re.sub(d,'',A)
		if J(A)%2!=0:A+='F'
		B=''
		for C in S(0,J(A),2):B+=A[C+1]+A[C]
		return B
	def r(text):return p.hexlify(text.encode('utf-16-be')).decode().upper()
	V=U(q);s=int(J(V)/2+1);t=f"{s:02X}91{V}";u='11';v='00';Y=re.sub(d,'',R);w=f"{J(Y):02X}91{U(Y)}";x='00';y='08';Z=r(T);z=f"{J(Z)//2:02X}";A0='a7'+z+Z;a=u+v+w+x+y+A0;H=t+a;L=J(a)//2;A.info(f"PDU编码: {H}");A.info(f"AT+CMGS长度: {L}")
	try:
		if c==e:
			async with l:
				try:
					with b.Serial(G,115200,timeout=5)as B:
						A.info(f"[direct模式] 新建串口: {G}");B.write(f);A.info(g);await C.sleep(.5);M=B.read_all().decode(errors=I);A.info(f"AT+CMGF=0 返回: {M}")
						if W not in M:return h
						B.write(f"AT+CMGS={L}\r".encode());A.info(f"发送: AT+CMGS={L}");F=X
						for P in S(30):
							await C.sleep(.1);E=B.read_all()
							if E:A.info(f"收到串口数据: {E}")
							F+=E
							if b'>'in F:A.info(i);break
						else:A.error(O);return O
						B.write(H.encode()+j);A.info(f"发送PDU+Ctrl+Z: {H}");F=X
						for P in S(100):
							await C.sleep(.1);E=B.read_all()
							if E:A.info(f"收到串口数据: {E}")
							F+=E;D=F.decode(errors=I)
							if k in D:A.info(f"串口返回: {D}");A.info(m);return W
							elif n in D:A.info(f"串口返回: {D}");A.error(f"发送失败: {D}");return f"SEND_FAIL: {D}"
						A.warning(f"未知返回: {D}");return f"ERROR: {D}"
				except K as Q:A.exception(o);return f"串口异常: {Q}"
		else:
			B=b.Serial(G,115200,timeout=5);A.info(f"打开串口: {G}");B.write(f);A.info(g);await C.sleep(.5);M=B.read_all().decode(errors=I);A.info(f"AT+CMGF=0 返回: {M}")
			if W not in M:B.close();return h
			B.write(f"AT+CMGS={L}\r".encode());A.info(f"发送: AT+CMGS={L}");F=X
			for P in S(30):
				await C.sleep(.1);E=B.read_all()
				if E:A.info(f"收到串口数据: {E}")
				F+=E
				if b'>'in F:A.info(i);break
			else:B.close();A.error(O);return O
			B.write(H.encode()+j);A.info(f"发送PDU+Ctrl+Z: {H}");F=X
			for P in S(100):
				await C.sleep(.1);E=B.read_all()
				if E:A.info(f"收到串口数据: {E}")
				F+=E;D=F.decode(errors=I)
				if k in D:A.info(f"串口返回: {D}");B.close();A.info(m);return W
				elif n in D:A.info(f"串口返回: {D}");B.close();A.error(f"发送失败: {D}");return f"SEND_FAIL: {D}"
			B.close();A.warning(f"未知返回: {D}");return f"ERROR: {D}"
	except K as Q:A.exception(o);return f"串口异常: {Q}"
async def s(websocket,path=Y):
	o='cmd';j='无返回';i='命令执行超时';h='\r\n';P='result';N='id';E=websocket;L('ws_handler loaded',E,path);k.add(E);L(f"WebSocket客户端已连接: {E.remote_address}")
	try:
		async for Z in E:
			B=Y;J=Y
			if m(Z,Q):
				try:
					R=F.loads(Z)
					if m(R,dict)and o in R:J=R[o];B=R.get(N)
					else:J=Z.strip()
				except K:J=Z.strip()
			else:await E.send(F.dumps({'error':'不支持二进制消息'},ensure_ascii=H));continue
			if not J:continue
			if J.startswith('SEND_SMS'):p=J.split(',',3);f=await r(p);D={N:B,P:f}if B else f;await E.send(F.dumps(D,ensure_ascii=H)if B else f);continue
			if not J.endswith('\r')and not J.endswith('\n'):J+='\r'
			T=J
			if c==e:
				async with l:
					try:
						with b.Serial(G,115200,timeout=5)as a:
							a.reset_input_buffer();a.reset_output_buffer()
							if not T.endswith(h):T=T.rstrip(h)+h
							a.write(T.encode());g=X
							for t in S(50):
								await C.sleep(.1);R=a.read_all()
								if R:g+=R
								O=g.decode(errors=I).strip()
								if W in O or'ERROR'in O or'BUSY'in O:break
							O=g.decode(errors=I).strip();A.info(f"串口返回: {O}");D={N:B,P:O}if B else O;await E.send(F.dumps(D,ensure_ascii=H)if B else O)
					except K as M:A.exception('串口命令异常');D={N:B,P:Q(M)}if B else Q(M);await E.send(F.dumps(D,ensure_ascii=H)if B else Q(M))
				continue
			else:
				try:
					A.info(f"调用tom_modem参数: tom_modem {G} -c '{T}'");n=await C.create_subprocess_exec(d,G,'-c',T,stdout=C.subprocess.PIPE,stderr=C.subprocess.PIPE)
					try:q,s=await C.wait_for(n.communicate(),timeout=5)
					except C.TimeoutError:A.error(i);D={N:B,P:i}if B else i;await E.send(F.dumps(D,ensure_ascii=H)if B else D);n.kill();continue
					U=q.decode(errors=I).strip();V=s.decode(errors=I).strip();A.info(f"tom_modem标准输出: {U}");A.info(f"tom_modem标准错误: {V}")
					if U:A.info(f"推送到前端: {U}");D={N:B,P:U}if B else U;await E.send(F.dumps(D,ensure_ascii=H)if B else U)
					elif V:A.info(f"推送到前端: {V}");D={N:B,P:V}if B else V;await E.send(F.dumps(D,ensure_ascii=H)if B else V)
					else:A.info('推送到前端: 无返回');D={N:B,P:j}if B else j;await E.send(F.dumps(D,ensure_ascii=H)if B else j)
				except K as M:A.exception('执行tom_modem命令异常');D={N:B,P:Q(M)}if B else Q(M);await E.send(F.dumps(D,ensure_ascii=H)if B else Q(M))
	except K as M:L(f"WebSocket客户端断开: {M}")
	finally:k.discard(E)
def t():C=D.path.join(D.path.dirname(D.path.abspath(__file__)),'web');D.chdir(C);A=B[O][E]if O in B and E in B[O]else 8001;F=http.server.SimpleHTTPRequestHandler;G=j.TCPServer(('',A),F);L(f"HTTP 服务器已启动: http://0.0.0.0:{A}/");G.serve_forever()
u=i.Thread(target=t,daemon=U)
u.start()
async def v():A=await h.serve(s,B[N][T],B[N][E]);L(f"WebSocket服务器已启动: ws://{B[N][T]}:{B[N][E]}");await A.wait_closed()
if __name__=='__main__':
	try:
		if sys.platform=='win32':C.set_event_loop_policy(C.WindowsSelectorEventLoopPolicy())
		try:M=C.new_event_loop();C.set_event_loop(M)
		except K as Z:M=C.get_event_loop()
		try:M.run_until_complete(v())
		except f:L('\n正在关闭服务...')
		finally:
			a=C.all_tasks(M)
			for w in a:w.cancel()
			M.run_until_complete(C.gather(*a,return_exceptions=U));M.close()
	except f:L('主动停止监听短信')
	except K as Z:L(f"程序启动错误: {Z}")