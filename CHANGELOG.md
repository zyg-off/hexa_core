# Changelog

## 1.0.0-beta.1 — 2026-11-18

Première bêta de la fondation reprise à zéro (l'ancienne version 1.4.0 n'est conservée que dans la sauvegarde).

- **Démarrage sûr** : sans oxmysql ou sans framework, message clair + arrêt propre du core.
- **Versions bêta** : `1.0.0-beta.10` est reconnue plus récente que `beta.9`, et une version finale plus récente que sa bêta. `Hexa.apiLevel` (1.4.0) garde les ressources Hexa existantes compatibles ; exports `Version` et `ApiLevel`.
- **IDs permanents** : stockés en base, jamais réutilisés, numérotation initiale des personnages existants dans l'ordre de création, suppression de personnage (`Hexa.DeleteCharacter`, événement `hexa_core:characterDeleted`), dernière connexion (`Hexa.LastSeen`).
- **`Hexa.Profile`** : fiche joueur complète en un appel.
- **Registre d'objets** : source unique (ox_inventory sinon framework), champs `stackable`, `limit`, `category`, `weapon`, `rare` ; `Hexa.RegisterItem`.
- **Service** : `Hexa.OnDuty`, `Hexa.SetDuty` (QBCore / QBox ; ESX n'a pas cette notion).
- **Grades et gangs** : `Hexa.SetGrade`, `Hexa.SetGang`, `Hexa.FireJob` (renvoi, même hors ligne).
- **Comptes d'entreprise** : droit de retrait par grade (`SocietyCanWithdraw`, `SocietyWithdraw`), virement (`SocietyTransfer`), journal en base (`SocietyHistory`, table `hexa_society_log`), découvert réglable, `CreateSociety` (hexa_banking). Réglages : `config_server.lua` → `Society`.
- **Dialogues** : nouveaux champs `password`, `pin`, `slider`, `time` (réponses revérifiées par le jeu) ; **panneau latéral** (`Dialog.Style = 'side'`) ; **manette** ; touches de validation / d'annulation réglables ; `Hexa.Menu` (petit menu liste) ; `Hexa.InputDialog` (même forme que `lib.inputDialog` d'ox_lib).
- Vérification des versions : l'échec est maintenant visible en console.
- **Logs Discord refaits** : une seule file pour tout le serveur, un seul salon (`Logs.webhook`), regroupement (`groupSeconds`), anti-spam (`maxPerMinute`), renvoi sur limite de débit, fichier du jour (`logs/jour_NN.log`, cycle de `keepDays` fichiers, 2 Mo max), base `hexa_logs`.
- **Instances** : premier numéro réglable (`Instances.firstBucket`), joueur remis dans son instance si un autre script change son bucket (avertissement unique).
- **Points d'interaction** : boucle à fréquence fixe réglable (`Points.interval`), formes boîte et polygone, icône de carte (`blip`), texte 3D, prise en charge d'ox_target, nettoyage complet à l'arrêt de la ressource.
- **Sécurité** : exports sensibles surveillés (ressource étrangère signalée) et limités (`Security.maxCallsPerMinute`).
- **Commandes** : `hexa_debug` (debug à chaud) et `hexa_check` (bilan de santé).
- 1 757 tests sur ESX, QBCore et QBox + 60 tests de l'interface.
