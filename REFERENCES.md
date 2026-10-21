# References

**Glucose Motion — From wearable sensors to athlete feedback**  
Yunus Emre Sahin · MSc Sports Technology · KTH Royal Institute of Technology  
Poster and prototype project, October 2026

[Project overview](README.md) · [Feedback calculations](docs/FEEDBACK.md)

## Scientific literature

### 1. CGM accuracy in sport

Bauhaus H, Erdogan P, Braun H, Thevis M. Continuous Glucose Monitoring (CGM) in Sports—A Comparison between a CGM Device and Lab-Based Glucose Analyser under Resting and Exercising Conditions in Athletes. *International Journal of Environmental Research and Public Health*. 2023;20(15):6440.  
**DOI:** [10.3390/ijerph20156440](https://doi.org/10.3390/ijerph20156440)

Relevance: differences between interstitial sensor readings and capillary laboratory measurements under resting and exercising conditions. Supports the accuracy and interpretation limitations.

### 2. Libre 3 during strength training

Matzka M, Ørtenblad N, Lenk M, Sperlich B. Accuracy of a continuous glucose monitoring system applied before, during, and after an intense leg-squat session with low- and high-carbohydrate availability in young adults without diabetes. *European Journal of Applied Physiology*. 2024;124:3557–3569.  
**DOI:** [10.1007/s00421-024-05557-5](https://doi.org/10.1007/s00421-024-05557-5)

Relevance: strength-training context, phase-dependent accuracy and caution about interpreting post-exercise CGM. This evaluated Libre 3, not a validation of this app or every Libre 3 Plus use condition.

### 3. Exercise and meal context

DuBose SN, Li Z, Sherr JL, Beck RW, Tamborlane WV, Shah VN; CGM in Healthy Individuals without Diabetes Study Group. Effect of Exercise and Meals on Continuous Glucose Monitor Data in Healthy Individuals Without Diabetes. *Journal of Diabetes Science and Technology*. 2021;15(3):593–599.  
**DOI:** [10.1177/1932296820905904](https://doi.org/10.1177/1932296820905904)

Relevance: recording exercise and meals alongside glucose in people without diabetes. Different population/protocol/device from this N=1 project.

### 4. Sport applications and interpretation

Bowler A-LM, Whitfield J, Marshall L, Coffey VG, Burke LM, Cox GR. The Use of Continuous Glucose Monitors in Sport: Possible Applications and Considerations. *International Journal of Sport Nutrition and Exercise Metabolism*. 2023;33:121–132.  
**DOI:** [10.1123/ijsnem.2022-0139](https://doi.org/10.1123/ijsnem.2022-0139)

Relevance: opportunities and limitations of context-based interpretation; glucose readings alone do not validate fueling adequacy or improved performance.

### 5. Interpretation in athletes

Flockhart M, Larsen FJ. Continuous Glucose Monitoring in Endurance Athletes: Interpretation and Relevance of Measurements for Improving Performance and Health. *Sports Medicine*. 2024;54:247–255. Published online 2 September 2023.  
**DOI:** [10.1007/s40279-023-01910-4](https://doi.org/10.1007/s40279-023-01910-4)

Relevance: physiological interpretation and the evidence gap between collecting CGM readings and establishing useful performance or health guidance. Endurance discussion is background, not direct validation of a strength-training recommendation.

### 6. Pre-exercise carbohydrate timing

Moseley L, Lancaster GI, Jeukendrup AE. Effects of timing of pre-exercise ingestion of carbohydrate on subsequent metabolism and cycling performance. *European Journal of Applied Physiology*. 2003;88:453–458. Published online 27 November 2002.  
**DOI:** [10.1007/s00421-002-0728-8](https://doi.org/10.1007/s00421-002-0728-8)

Relevance: rationale for investigating timing as a variable. The study used a glucose drink and cycling; its results cannot be transferred directly to banana/coffee and strength training.

## Manufacturer and technical sources

### 7. Sensor setup and product description

Abbott Diabetes Care. *FreeStyle Libre 3 Plus Getting Started Guide (Libre app).*  
[Manufacturer guide](https://www.freestyle.abbott/content/dam/adc/freestyle/countries/us-en/documents/Brochure_FreeStyleLibre_3_Plus_Getting_Started_Guide_Libre_App.pdf)

The US guide is a technical background source. The Swedish app/device instructions supplied with the participant's sensor govern local setup; product and app features vary by market.

### 8. Interstitial glucose measurement

Abbott Diabetes Care. *Understanding interstitial glucose measurement: FreeStyle Libre 3 System.*  
[Manufacturer information](https://pro.freestyle.abbott/content/dam/adc/pro/countries/uk-en/documents/FSL3.pdf)

Relevance: sensor glucose is measured in interstitial fluid; blood and sensor glucose should not be treated as identical measurements at every instant.

### 9. LibreLinkUp sharing

Abbott Diabetes Care. *LibreLinkUp App User's Manual.*  
[Official user manual](https://freestyleserver.com/Payloads/IFU/2026/q1/ART53380_001_rev_A_pub/languages/en/x_librelinkup/DOC53380/users_manual.html)

Relevance: official sharing workflow and connectivity/transmission limitations. The Glucose Motion cloud implementation is unofficial; this manual does not document or endorse its API integration.

## Poster image attribution

If the original Libre 3 Plus product image remains on the poster: Abbott FreeStyle Libre 3 Plus product image, original source recorded in the poster:  
[Product image source](https://s30917.pcdn.co/wp-content/uploads/FSL3Plus_800-600x600.jpg)

Manufacturer images and trademarks belong to their respective owners. A source credit is not a licence; the image itself is not redistributed in this repository.

## Use on the poster

Suggested section mapping: **CGM in Sport [1, 4, 5, 8]**; **Experimental Method [3, 6, 7]**; **Limitations [1, 2, 4, 5]**; **Data sharing [9]**. Keep citation numbers next to the relevant statements; the QR provides the complete bibliography. Only cite a source where its contents support the actual statement.

The perceived-exertion reference from an earlier poster draft is omitted because effort/RPE is no longer part of the final app and project scope. No published article validates the prototype's automatic feedback rules. Those rules and their limits are documented separately in [Feedback calculations](docs/FEEDBACK.md).

Bibliographic details checked against the article PDFs supplied for this project. Technical links accessed 21 October 2026.
