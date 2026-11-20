# Pixel2Play på iPhone

Pixel2Play körs i valfri diagnostik i observationsläget. Förslagen visas som VIS-status. Regelmotorn äger styrningen i det autonoma testläget.

Den lyckade [exportkörningen](https://github.com/Dhafen/flash-local-swiftlet/actions/runs/44592686942) byggde policy och decoder för fyra RGB-bildrutor från den [pinnade checkpointen](https://huggingface.co/elefantai/open-p2p/tree/5c52dce4aefbd4f50d24caccc2dcfda7bbd59719). En lokal kopia innehöll båda Core ML-paketen och ett schema 1-manifest med 182 433 505 använda parametrar. Policy-NRMSE var 0,0054–0,0065 och decoder-NRMSE 0,0034–0,0049 för två syntetiska seeds. Referensen i exporten är repots egna PyTorch-implementation med explicit attention. End-to-end-paritet med upstream-inferens och WoW-kvalitet återstår.

| Del | Lokal implementation | Verifieringsgap |
| --- | --- | --- |
| Bild | Metal kopierar hela renderingsytan högst en gång per sekund, tar bort bildremsan och area-medelvärdesbildar till RGB CHW 192 × 192. Swift skalar byte till 0–1. Exporten tillämpar EfficientNet-normalisering. | Referensens resize och färgkedja behöver jämföras pixel för pixel på fasta bildrutor. |
| Handling | Swift samplar kategoriskt från de fyra första logits-slotarna. De första fyra är tangentbord. I diagnos reduceras de till ett riktningstecken eller WAIT. | Kör samma logit- och RNG-fixtures mot referensen. Manifestets etikett om greedy sampling beskriver en äldre artefakt och speglar inte Swift-koden. |
| Historik | Fyra rutor, neutral action history i diagnostik, generation säkrar reset och ignorerar gamla resultat. | Referensen kör med längre kontext och faktisk exekverad åtgärd. Den lokala diagnosen har ingen återkoppling från styrningen. |
| Körning | Runtime kontrollerar form och manifest före Core ML. Exporten testades på CPU. iOS begär CPU och Neural Engine. | Modellkompilering, ANE-delegering, första/kontinuerlig inferenstid, RAM och effekt saknar enhetsdata. |

Teknisk referens för handlingstokens, historik och sampling. [Upstream action mapping](https://github.com/elefant-ai/open-p2p/blob/main/elefant/data/action_mapping.py) · [Upstream inference](https://github.com/elefant-ai/open-p2p/blob/main/elefant/policy_model/inference.py)

För paritet krävs samma riktiga bildrutor, normalisering och resize, tidsordnad historik inklusive icke-neutrala tangentbords- och mustokens, samt jämförelse av logits och beslut med fixerade seeds. Testa en omslagspunkt för historiken och återställning. Kontrollera enhetens kompilerade modell separat.
