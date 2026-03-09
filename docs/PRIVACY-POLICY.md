# Politique de confidentialite — SchoolTrack

> Version 1.0 — Mars 2026
> Responsable du traitement : Etablissement scolaire utilisant SchoolTrack
> Contact DPO : a definir par l'etablissement

---

## 1. Introduction

SchoolTrack est une application de gestion des presences pour les sorties scolaires.
Cette politique de confidentialite decrit les donnees personnelles collectees,
les finalites du traitement, les mesures de protection et les droits des personnes
concernees conformement au **Reglement General sur la Protection des Donnees (RGPD)**
— Reglement (UE) 2016/679.

---

## 2. Donnees collectees

### 2.1 Donnees des eleves

| Donnee | Finalite | Base legale |
|--------|----------|-------------|
| Nom, prenom | Identification lors des sorties | Interet legitime (securite des eleves) |
| Email | Communication des QR codes digitaux | Consentement |
| Photo (optionnel) | Identification visuelle | Consentement parental |
| Consentement parental | Preuve du consentement RGPD | Obligation legale |
| Presences (scans) | Suivi de la securite en sortie | Interet legitime |
| Classe | Organisation scolaire | Interet legitime |

### 2.2 Donnees des utilisateurs (personnel)

| Donnee | Finalite | Base legale |
|--------|----------|-------------|
| Nom, prenom | Identification dans le systeme | Execution du contrat de travail |
| Email | Authentification + notifications | Execution du contrat de travail |
| Mot de passe (hache) | Securite d'acces | Interet legitime |
| Secret 2FA (chiffre) | Authentification renforcee | Interet legitime |
| Adresse IP, user-agent | Journalisation de securite | Interet legitime |

### 2.3 Donnees techniques

| Donnee | Finalite | Base legale |
|--------|----------|-------------|
| Logs d'audit | Tracabilite et conformite RGPD | Obligation legale |
| Identifiants de bracelets (token_uid) | Suivi anonyme des presences | Interet legitime |

---

## 3. Principes de traitement

SchoolTrack respecte les principes fondamentaux du RGPD :

- **Minimisation** : seules les donnees strictement necessaires sont collectees
- **Limitation de finalite** : les donnees sont utilisees uniquement pour la gestion
  des presences lors des sorties scolaires
- **Exactitude** : les utilisateurs autorises peuvent corriger les donnees (droit de rectification)
- **Limitation de conservation** : les donnees sont conservees selon les durees definies (section 6)
- **Integrite et confidentialite** : les donnees sont protegees par chiffrement (section 4)
- **Licite** : chaque traitement repose sur une base legale identifiee

---

## 4. Mesures de protection

### 4.1 Chiffrement

| Couche | Technologie | Donnees protegees |
|--------|-------------|-------------------|
| En transit | TLS 1.3 (HTTPS obligatoire) | Toutes les communications |
| Au repos (serveur) | AES-256-GCM par colonne | Noms, prenoms, emails, secrets 2FA |
| Au repos (mobile) | SQLCipher AES-256 | Base de donnees locale entiere |
| Export | ZIP AES-256 (optionnel) | Fichiers CSV exportes |

### 4.2 Controle d'acces

- Authentification par mot de passe (bcrypt, cout 12) + 2FA optionnel (TOTP)
- Quatre roles avec permissions differenciees (principe du moindre privilege)
- Verrouillage de compte apres 5 tentatives echouees
- Sessions JWT avec expiration (30 min access / 24h refresh)

### 4.3 Tracabilite

- Journal d'audit enregistrant toutes les actions sensibles
- Conservation des logs pendant 12 mois minimum
- Protection en lecture seule (acces restreint a la Direction et Admin Technique)

---

## 5. Droits des personnes concernees

Conformement aux articles 15 a 21 du RGPD, les personnes concernees
(ou leurs representants legaux pour les mineurs) disposent des droits suivants :

### 5.1 Droit d'acces (art. 15)

Les donnees personnelles d'un eleve peuvent etre exportees au format JSON
via l'endpoint `GET /api/v1/students/{id}/data-export`.
L'export inclut : donnees personnelles, classes, sorties, presences,
assignations de bracelets et alertes.

**Procedure** : demande aupres de la Direction via le formulaire de l'etablissement.
La Direction genere l'export depuis le tableau de bord SchoolTrack.

### 5.2 Droit de rectification (art. 16)

Les donnees d'un eleve (nom, prenom, email) peuvent etre corrigees
via l'interface d'edition du tableau de bord.

**Procedure** : demande aupres de la Direction. Correction effectuee
dans le systeme avec journalisation de la modification.

### 5.3 Droit a l'effacement (art. 17)

SchoolTrack implemente une **suppression logique** (soft delete) :
- L'eleve est marque comme supprime (`is_deleted = true`)
- Ses donnees sont conservees pour l'historique et la tracabilite
- Il est exclu de toutes les listes et operations courantes
- La date et l'auteur de la suppression sont enregistres

**Pourquoi pas de suppression physique ?**
La conservation de l'historique est necessaire pour garantir la tracabilite
des presences lors des sorties scolaires (obligation de securite).

### 5.4 Droit a la portabilite (art. 20)

L'export JSON structure (section 5.1) permet la portabilite des donnees
vers un autre systeme.

### 5.5 Droit d'opposition (art. 21)

Pour exercer un droit d'opposition au traitement, contacter le DPO
de l'etablissement scolaire.

---

## 6. Durees de conservation

| Donnee | Duree | Justification |
|--------|-------|---------------|
| Donnees des eleves actifs | Duree de scolarite | Necessite du traitement |
| Donnees des eleves supprimes | 5 ans apres suppression logique | Tracabilite et obligations legales |
| Logs d'audit | 12 mois | Conformite RGPD (art. 30) |
| Presences (scans) | 5 ans | Historique de securite |
| Comptes utilisateurs | Duree du contrat de travail | Necessite du traitement |

---

## 7. Sous-traitants et transferts

| Sous-traitant | Finalite | Localisation |
|---------------|----------|-------------|
| Hebergeur VPS | Hebergement serveur et BDD | Union europeenne |
| Let's Encrypt | Certificats TLS | International (non-profit) |

Aucun transfert de donnees personnelles hors de l'Espace Economique Europeen (EEE).

---

## 8. Violation de donnees

En cas de violation de donnees personnelles :
1. Le responsable du traitement est notifie immediatement
2. L'autorite de controle (APD en Belgique) est informee dans les 72 heures
3. Les personnes concernees sont notifiees si le risque est eleve
4. L'incident est documente dans le journal d'audit

---

## 9. Contact

Pour exercer vos droits ou pour toute question relative a la protection
de vos donnees personnelles, contactez :

- **DPO de l'etablissement** : [a definir par l'etablissement]
- **Direction de l'etablissement** : via le formulaire de contact officiel

---

## 10. Modifications

Cette politique peut etre mise a jour. La version en vigueur est toujours
accessible depuis l'application SchoolTrack et dans le depot du projet
(`docs/PRIVACY-POLICY.md`).

Derniere mise a jour : mars 2026.
