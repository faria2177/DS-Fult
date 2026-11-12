"""Private boundary detector; optional trained ONNX document mask model."""
import os
import cv2
import numpy as np

def ordered(points):
    pts = np.asarray(points, np.float32).reshape(4, 2)
    s = pts.sum(axis=1); d = pts[:, 0] - pts[:, 1]
    idx = [np.argmin(s), np.argmax(d), np.argmax(s), np.argmin(d)]
    if len(set(map(int, idx))) != 4: raise ValueError("Repeated corners")
    return pts[idx]

def contrast(image, quad):
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB).astype(np.float32)
    h, w = image.shape[:2]
    center = np.mean(quad, axis=0); strengths = []
    for side in range(4):
        a, b = quad[side], quad[(side + 1) % 4]
        v = b - a; length = np.linalg.norm(v)
        if length < 12: return 0.0
        n = np.array([-v[1], v[0]], np.float32) / length
        if np.linalg.norm((a+b)/2 + n*6 - center) < np.linalg.norm((a+b)/2 - center): n = -n
        # Shiny/gold paper sometimes becomes indistinguishable from notebook
        # paper at 5px; compare several nearby distances while retaining
        # evidence from every side (not just a single strong text line).
        side_scores = []
        reach = max(8, min(20, round(max(h, w) * .016)))
        for offset in (5, max(8, reach // 2), reach):
            samples = []
            for t in np.linspace(.17, .83, 8):
                p = a + t*v
                inside = np.rint(p-n*offset).astype(int)
                outside = np.rint(p+n*offset).astype(int)
                if not (0 <= inside[0] < w and 0 <= outside[0] < w and 0 <= inside[1] < h and 0 <= outside[1] < h):
                    continue
                delta = np.linalg.norm(lab[inside[1],inside[0]]-lab[outside[1],outside[0]])
                samples.append(np.clip((delta-9)/35,0,1))
            side_scores.append(float(np.mean(samples)) if samples else 0.)
        strengths.append(max(side_scores))
    return float(.65*np.mean(strengths)+.35*np.mean([x>=.48 for x in strengths]))

def evaluate(image, contour, source, model=False):
    h,w=image.shape[:2]
    area=cv2.contourArea(contour)
    if not h*w*.13 < area < h*w*.95: return None
    hull=cv2.convexHull(contour)
    hullarea=cv2.contourArea(hull)
    if hullarea<=0 or area/hullarea<.72: return None
    approx=cv2.approxPolyDP(hull,.018*cv2.arcLength(hull,True),True)
    fitted=len(approx)!=4 or not cv2.isContourConvex(approx)
    corners=cv2.boxPoints(cv2.minAreaRect(contour)) if fitted else approx.reshape(4,2)
    try: quad=ordered(corners)
    except ValueError: return None
    if not cv2.isContourConvex(quad): return None
    coverage=cv2.contourArea(quad)/(h*w)
    if not .17<=coverage<=.94: return None
    if np.min(quad[:,0])<=w*.004 or np.max(quad[:,0])>=w*.996 or np.min(quad[:,1])<=h*.004 or np.max(quad[:,1])>=h*.996: return None
    center=np.mean(quad,axis=0)
    if abs(center[0]/w-.5)>.30 or abs(center[1]/h-.5)>.30: return None
    sides=[np.linalg.norm(quad[(i+1)%4]-quad[i]) for i in range(4)]
    width=(sides[0]+sides[2])/2; height=(sides[1]+sides[3])/2
    ratio=max(width,height)/max(1.,min(width,height))
    if not 1.08<=ratio<=2.20: return None
    card=1.48<=ratio<=1.82
    if card and not .19<=coverage<=.86: return None
    if not card and coverage<.30: return None
    edge=contrast(image,quad)
    if edge<.37: return None
    confidence=float(np.clip(.52+.27*edge+.12*min(1,area/hullarea)+.07*min(1,coverage/.5)+(0.05 if model else 0)-(0.08 if fitted else 0),0,.99))
    if confidence<(.90 if card else .86): return None
    normalized=quad/np.array([w,h],np.float32)
    keys=["top_left","top_right","bottom_right","bottom_left"]
    return {"success":True,"document_type":"id_card" if card else "document",
            "confidence":round(confidence,4),
            "corners":{key:[round(float(p[0]),6),round(float(p[1]),6)] for key,p in zip(keys,normalized)},
            "engine":"onnx" if model else "opencv","_rank":confidence+(.04 if model else 0)}

class DocumentBoundaryDetector:
    def __init__(self,model_path=None):
        self.session=None
        if model_path:
            from onnxruntime import InferenceSession
            self.session=InferenceSession(model_path,providers=["CPUExecutionProvider"])
            self.input_name=self.session.get_inputs()[0].name

    def model_mask(self,image):
        rgb=cv2.resize(cv2.cvtColor(image,cv2.COLOR_BGR2RGB),(512,512)).astype(np.float32)/255
        out=np.asarray(self.session.run(None,{self.input_name:rgb.transpose(2,0,1)[None]})[0])
        if out.ndim==4: out=out[0]
        if out.ndim==3: out=out[1] if out.shape[0]>1 else out[0]
        if out.ndim!=2: raise ValueError("Model must produce a foreground mask")
        if np.min(out)<0 or np.max(out)>1: out=1/(1+np.exp(-np.clip(out,-30,30)))
        return (cv2.resize(out.astype(np.float32),(image.shape[1],image.shape[0]))>.5).astype(np.uint8)*255

    def detect(self,jpeg,prefer_card=False):
        image=cv2.imdecode(np.frombuffer(jpeg,np.uint8),cv2.IMREAD_COLOR)
        if image is None or min(image.shape[:2])<64: return {"success":False,"reason":"invalid_image"}
        h,w=image.shape[:2]; scale=min(1,1280/max(h,w))
        if scale<1: image=cv2.resize(image,(round(w*scale),round(h*scale)),interpolation=cv2.INTER_AREA)
        h,w=image.shape[:2]
        step=max(4,round(min(h,w)*.08))
        corners=np.concatenate([image[:step,:step].reshape(-1,3),image[:step,-step:].reshape(-1,3),image[-step:,:step].reshape(-1,3),image[-step:,-step:].reshape(-1,3)])
        bg=np.median(corners,axis=0)
        diff=np.linalg.norm(image.astype(np.float32)-bg,axis=2)
        hsv=cv2.cvtColor(image,cv2.COLOR_BGR2HSV)
        masks=[("background",(diff>43).astype(np.uint8)*255),
               ("colour",cv2.inRange(hsv,(0,45,65),(179,255,255)))]
        grey=cv2.cvtColor(image,cv2.COLOR_BGR2GRAY)
        edge=cv2.Canny(cv2.GaussianBlur(grey,(5,5),0),45,125)
        masks.append(("edge",cv2.morphologyEx(edge,cv2.MORPH_CLOSE,np.ones((5,5),np.uint8))))
        if self.session is not None:
            try: masks.insert(0,("onnx",self.model_mask(image)))
            except Exception: pass
        proposals=[]
        for name,mask in masks:
            if name!="edge":
                mask=cv2.morphologyEx(mask,cv2.MORPH_OPEN,np.ones((5,5),np.uint8))
                mask=cv2.morphologyEx(mask,cv2.MORPH_CLOSE,np.ones((5,5),np.uint8))
            contours,_=cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
            for contour in sorted(contours,key=cv2.contourArea,reverse=True)[:10]:
                candidate=evaluate(image,contour,name,model=name=="onnx")
                if candidate:
                    if prefer_card and candidate["document_type"]=="id_card": candidate["_rank"]+=.04
                    proposals.append(candidate)
        if not proposals: return {"success":False,"reason":"uncertain_boundary"}
        best=max(proposals,key=lambda c:c["_rank"])
        best.pop("_rank")
        return best

def create_detector():
    return DocumentBoundaryDetector(os.environ.get("DOCSCAN_ONNX_MODEL") or None)
