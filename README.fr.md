<div align="center">

<img src="Assets/FanBar-readme-banner-light.png" alt="FanBar — contrôle des ventilateurs natif pour macOS, gratuit et open source" width="100%">

# FanBar — contrôle des ventilateurs du Mac, gratuit et open source

> Une app gratuite et open source pour contrôler les ventilateurs du Mac depuis la barre des menus. Surveillez les températures et la vitesse des ventilateurs, fixez une vitesse en tr/min ou créez des courbes de ventilation selon la température.

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.fr.md"><strong>Français</strong></a>
</p>

<p align="center">
  <a href="https://getfanbar.com/?utm_source=github&utm_medium=referral&utm_campaign=readme"><strong>getfanbar.com</strong></a> ·
  <a href="https://getfanbar.com/is-fanbar-safe?utm_source=github&utm_medium=referral&utm_campaign=readme">FanBar est-il sûr ?</a> ·
  <a href="https://getfanbar.com/compare/macs-fan-control?utm_source=github&utm_medium=referral&utm_campaign=readme">FanBar ou Macs Fan Control</a>
</p>

<p align="center">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="Licence : GPL-3.0">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/releases/latest">
    <img src="https://img.shields.io/github/v/release/helson-lin/FanBar?color=brightgreen" alt="version">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/releases">
    <img src="https://img.shields.io/github/downloads/helson-lin/FanBar/total?color=blue" alt="téléchargements">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/releases">
    <img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fhelson-lin%2FFanBar%2Fbadges%2Fdmg-downloads.json" alt="Téléchargements de DMG" title="Téléchargements cumulés des DMG de toutes les versions, mises à jour comprises ; actualisé chaque jour.">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/stargazers">
    <img src="https://img.shields.io/github/stars/helson-lin/FanBar?color=yellow" alt="étoiles">
  </a>
</p>

<p align="center">
  <a href="#-captures-décran">Captures</a> •
  <a href="#-points-forts">Points forts</a> •
  <a href="#️-téléchargement">Téléchargement</a> •
  <a href="#-utilisation">Utilisation</a> •
  <a href="#️-compilation-et-exécution">Compilation</a> •
  <a href="#️-architecture">Architecture</a> •
  <a href="#-intégration-continue-et-publication">Publication</a> •
  <a href="#-signaler-un-problème">Problèmes</a>
</p>

</div>

FanBar fonctionne sous macOS 11 Big Sur et versions ultérieures, sur les Mac Apple Silicon et Intel compatibles qui exposent des données de ventilateurs lisibles via AppleSMC. Au quotidien, il laisse macOS gérer le refroidissement automatiquement pour rester sûr et silencieux ; le contrôle manuel n’est disponible qu’après l’autorisation du service de contrôle signé.

## FanBar en bref

FanBar est une app native pour la barre des menus de macOS, gratuite et open source, qui surveille les températures du CPU, du GPU, du SSD et de la batterie ainsi que la vitesse des ventilateurs. Le refroidissement reste confié à la gestion automatique de macOS ; un contrôle manuel borné n’est proposé qu’après votre autorisation explicite du helper signé.

- **Mac pris en charge :** macOS 11 Big Sur ou ultérieur, sur les Mac Apple Silicon et Intel qui exposent des données de ventilateurs lisibles via AppleSMC.
- **Modes de refroidissement :** Automatique, vitesse cible fixe, et les profils Silencieux, Équilibré, Performance et Extrême ; chaque profil a sa propre courbe température → vitesse modifiable.
- **Limites de sécurité :** les vitesses cibles restent dans la plage matérielle indiquée par chaque ventilateur, et FanBar tente de revenir en mode Automatique quand un profil expire, quand l’app quitte, quand la connexion est perdue ou quand le helper échoue. Voir [ce que le helper root peut et ne peut pas faire](https://getfanbar.com/is-fanbar-safe?utm_source=github&utm_medium=referral&utm_campaign=readme).
- **Comparaison avec Macs Fan Control :** lisez la [comparaison étayée par le code source](https://getfanbar.com/compare/macs-fan-control?utm_source=github&utm_medium=referral&utm_campaign=readme).
- **Téléchargement :** utilisez la [dernière version notarisée sur GitHub](https://github.com/helson-lin/FanBar/releases/latest) ; aucun compte, abonnement ni publicité.
- **Compatibilité constatée :** consultez la [matrice des appareils avec sources](https://getfanbar.com/compatibility?utm_source=github&utm_medium=referral&utm_campaign=readme) pour voir ce qui a réellement été observé sur chaque Mac.

Le site officiel publie un fichier [llms.txt](https://getfanbar.com/llms.txt?utm_source=github&utm_medium=referral&utm_campaign=readme) concis pour les moteurs de réponse et les agents qui ont besoin d’informations de référence sur le produit.


## 📸 Captures d’écran

Interface française en apparence claire et sombre. Passez à l’anglais, au chinois simplifié ou traditionnel, au japonais ou au russe dans **Réglages → Général → Langue de l’interface**, sans redémarrer.

<table>
  <tr>
    <th>Clair</th>
    <th>Sombre</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-menu-light-fr.png" alt="Fenêtre de FanBar dans la barre des menus (Clair)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-menu-dark-fr.png" alt="Fenêtre de FanBar dans la barre des menus (Sombre)" width="100%"></td>
  </tr>
</table>

Sur un Mac à deux ventilateurs, le panneau les affiche côte à côte, chacun avec sa vitesse, son état et sa plage. Cette capture vient d’un MacBook Pro (M2 Max) en profil Équilibré.

<table>
  <tr>
    <th>Clair</th>
    <th>Sombre</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-menu-dual-fan-light-fr.png" alt="Fenêtre de FanBar dans la barre des menus, MacBook Pro à deux ventilateurs (Clair)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-menu-dual-fan-dark-fr.png" alt="Fenêtre de FanBar dans la barre des menus, MacBook Pro à deux ventilateurs (Sombre)" width="100%"></td>
  </tr>
</table>

Refroidissement associe à chaque profil du panneau sa propre courbe température → vitesse modifiable.

<table>
  <tr>
    <th>Clair</th>
    <th>Sombre</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-settings-cooling-light-fr.png" alt="Réglages de refroidissement de FanBar (Clair)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-settings-cooling-dark-fr.png" alt="Réglages de refroidissement de FanBar (Sombre)" width="100%"></td>
  </tr>
</table>

Apparence permet de choisir l’icône de la barre des menus et ce qu’affiche l’élément d’état, avec un aperçu en direct dans une barre des menus simulée.

<table>
  <tr>
    <th>Clair</th>
    <th>Sombre</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-settings-appearance-light-fr.png" alt="Réglages d’apparence de FanBar (Clair)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-settings-appearance-dark-fr.png" alt="Réglages d’apparence de FanBar (Sombre)" width="100%"></td>
  </tr>
</table>

Général regroupe la vérification locale de compatibilité, l’état du service de contrôle, le retour automatique, les notifications, la langue, l’ouverture à la connexion et les mises à jour. Journal enregistre les températures et la vitesse des ventilateurs au format CSV. Les pages de réglages longues défilent.

<table>
  <tr>
    <th>Clair</th>
    <th>Sombre</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-settings-general-light-fr.png" alt="Réglages généraux de FanBar (Clair)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-settings-general-dark-fr.png" alt="Réglages généraux de FanBar (Sombre)" width="100%"></td>
  </tr>
</table>

## ✨ Points forts

- **État visible d’un coup d’œil** — Affichez l’icône, la température du CPU, la vitesse moyenne des ventilateurs ou les deux, côte à côte ou superposées pour gagner de la place dans la barre des menus.
- **Six icônes pour la barre des menus** — Tourbillon, Anneau, Épais, Hélice, Grille ou Contour, toutes ajustées optiquement aux icônes du système ; le centre devient plein lorsque FanBar contrôle les ventilateurs. L’icône tourne avec les ventilateurs et ralentit jusqu’à l’arrêt quand ils s’arrêtent ; désactivez cette animation dans **Réglages → Apparence** pour garder l’icône immobile et économiser un peu de CPU.
- **Widget de bureau** — Sous macOS 14 ou ultérieur, ajoutez FanBar au bureau pour voir la vitesse moyenne, la vitesse de chaque ventilateur, la température du CPU et le mode de contrôle. WidgetKit planifie les actualisations ; elles ne sont pas à la seconde.
- **Visualisation en direct** — Chaque ventilateur affiche d’abord sa vitesse et sa plage de régime sur une jauge allant de 0 au maximum. Une grille compacte montre la charge du CPU, du GPU, de la mémoire et du disque, en vert, orange ou rouge selon le niveau ; le disque est évalué selon l’espace libre. Suivez les températures du CPU et du GPU, ainsi que celles du SSD et de la batterie quand le Mac les expose, sur un graphique des dix dernières minutes.
- **Plusieurs modes de refroidissement** — Revenez au contrôle automatique de macOS, fixez une vitesse cible ou choisissez le profil Silencieux, Équilibré, Performance ou Extrême.
- **Courbes de température intelligentes** — Chaque profil du panneau a sa propre courbe modifiable, qui ajuste progressivement les ventilateurs selon la température de la puce.
- **Source de température au choix** — Pilotez la courbe avec la température du CPU, du GPU ou du SSD ; si un capteur est indisponible, le repli de sécurité habituel s’applique.
- **Alertes de température élevée** — Activez, si vous le souhaitez, des notifications macOS quand le CPU ou le GPU atteint le seuil choisi (60–105 °C, 90 °C par défaut) ; chaque épisode de surchauffe ne déclenche qu’une alerte, réarmée après refroidissement. Choisissez un son d’alerte, joué même si les sons des notifications sont désactivés ou si une concentration est active. En cas de surchauffe, le panneau propose de passer au refroidissement maximal en un clic.
- **Journal CSV** — Enregistrez toutes les 2 à 60 secondes les températures du CPU, du GPU, du SSD et de la batterie, la vitesse des ventilateurs et le mode de contrôle dans des fichiers CSV situés dans `~/Library/Application Support/FanBar/Logs`, avec un nouveau fichier au lancement, à minuit ou jamais.
- **Repli de sécurité** — Les vitesses cibles sont limitées à la plage matérielle indiquée par chaque ventilateur. En cas de fermeture, de déconnexion ou de défaillance du service, FanBar tente de rendre le contrôle automatique à macOS.
- **Autorisation native** — Au premier lancement, FanBar explique pourquoi le service de contrôle est nécessaire et ouvre la bonne page des Réglages Système.
- **Six langues** — English, 简体中文, 繁體中文, 日本語, Русский et Français, ou la langue du système.

## ⬇️ Téléchargement

La dernière version notarisée se trouve sur la page [GitHub Releases](https://github.com/helson-lin/FanBar/releases/latest) :

| Puce | Fichier |
|:--|:--|
| Apple Silicon | `FanBar-<version>-arm64.dmg` |
| Intel | `FanBar-<version>-x86_64.dmg` |
| Universelle (utilisée par les mises à jour Sparkle) | `FanBar-<version>.dmg` |

### Installer avec Homebrew

Si [Homebrew](https://brew.sh) est installé, ajoutez ce dépôt comme tap puis installez :

```sh
brew tap helson-lin/fanbar https://github.com/helson-lin/FanBar.git
brew install --cask helson-lin/fanbar/fanbar
```

Le cask installe l’app universelle signée et notarisée, pour Apple Silicon et Intel,
dans `/Applications`. Lancez FanBar et autorisez son service de contrôle pour
activer le contrôle des ventilateurs. Si vous aviez déjà installé FanBar à la main,
quittez-le et placez `/Applications/FanBar.app` dans la corbeille avant de passer
par Homebrew.

FanBar peut se mettre à jour lui-même avec Sparkle. Pour mettre à jour explicitement avec Homebrew :

```sh
brew update
brew upgrade --cask helson-lin/fanbar/fanbar
```

Pour désinstaller, quittez d’abord FanBar, puis exécutez :

```sh
brew uninstall --cask helson-lin/fanbar/fanbar
```

Ajoutez `--zap` pour supprimer aussi les préférences et les caches. Homebrew peut
demander un mot de passe administrateur pour décharger le service de contrôle des ventilateurs.

### Configuration requise

- macOS 11 Big Sur ou ultérieur
- Un Mac qui expose les données des ventilateurs via AppleSMC
- Xcode 26 et Swift 6 pour compiler en local

> [!WARNING]
> AppleSMC est une interface matérielle non documentée. Réduire la vitesse des ventilateurs peut faire monter la température ; une vitesse élevée prolongée augmente le bruit, la consommation et l’usure mécanique. N’utilisez le contrôle manuel qu’en connaissant ces compromis, et préférez le mode Automatique ou le refroidissement intelligent au quotidien.

## 🚀 Utilisation

1. Lancez FanBar et lisez la température et la vitesse des ventilateurs dans la barre des menus.
2. Pour contrôler les ventilateurs, activez le contrôle des ventilateurs et suivez la demande d’autorisation de macOS.
3. Choisissez un profil du panneau ou une vitesse fixe dans la fenêtre. Choisissez **Automatique** à tout moment pour rendre le contrôle à macOS.

La vitesse fixe et les profils du panneau peuvent rendre le contrôle à macOS après 15 minutes, 30 minutes ou une heure.

Sous macOS 14 ou ultérieur, ouvrez l’éditeur de widgets du Centre de notifications et ajoutez **FanBar**. Le widget affiche le dernier relevé publié par l’app ; WidgetKit décide du moment des actualisations, donc utilisez la fenêtre de la barre des menus pour un suivi à la seconde.

### Changer la langue de l’interface

Ouvrez **Réglages → Général → Langue de l’interface** et choisissez :

- **System** — suit la langue actuelle du Mac (chinois simplifié ou traditionnel, japonais, russe, français ; sinon anglais)
- **English**
- **简体中文**
- **繁體中文**
- **日本語**
- **Русский**
- **Français**

Ce réglage s’applique à la fenêtre de la barre des menus, à la fenêtre des réglages, à l’accueil, aux messages d’état, aux erreurs du helper et au widget de bureau.

## 🤝 Communauté

[Contribuer](CONTRIBUTING.md) · [Code de conduite](CODE_OF_CONDUCT.md) · [Assistance](SUPPORT.md) · [Politique de sécurité](SECURITY.md)

Signalez toute vulnérabilité présumée par le canal privé décrit dans la politique de sécurité. Les rapports de bugs, les demandes de fonctionnalités et les questions d’utilisation passent par les formulaires publics ci-dessous.

## 🐛 Signaler un problème

Avant d’envoyer un signalement, cherchez parmi les [problèmes existants](https://github.com/helson-lin/FanBar/issues). Puis [choisissez un formulaire](https://github.com/helson-lin/FanBar/issues/new/choose) : bug, demande de fonctionnalité ou question d’utilisation. Un rapport de bug doit indiquer la version de FanBar, la version de macOS, le modèle de Mac et les étapes pour reproduire le problème. Retirez toute information personnelle des captures et des journaux.

## 🛠️ Compilation et exécution

Clonez le dépôt, puis créez un paquet d’app local :

```sh
zsh scripts/generate-icons.sh
FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
open dist/FanBar.app
```

`FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=-` crée un paquet ad hoc réservé à la vérification. Son helper privilégié ne peut pas s’authentifier ; utilisez une vraie identité de signature pour tester le contrôle des ventilateurs ou pour distribuer l’app. Voir [CONTRIBUTING.md](CONTRIBUTING.md) pour la configuration et la validation.

### Créer un DMG local

```sh
FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=- zsh scripts/build-dmg.sh
```

Le fichier produit par défaut est `dist/FanBar-<version>.dmg`. Pour une architecture précise :

```sh
FANBAR_ARCHS=arm64 FANBAR_APP_OUTPUT=dist/FanBar-arm64.app \
  FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
FANBAR_SIGN_IDENTITY=- FANBAR_DMG_OUTPUT=dist/FanBar-arm64.dmg zsh scripts/build-dmg.sh dist/FanBar-arm64.app

FANBAR_ARCHS=x86_64 FANBAR_APP_OUTPUT=dist/FanBar-x86_64.app \
  FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
FANBAR_SIGN_IDENTITY=- FANBAR_DMG_OUTPUT=dist/FanBar-x86_64.dmg zsh scripts/build-dmg.sh dist/FanBar-x86_64.app
```

Vérifiez la signature, l’architecture et la structure d’installation d’un DMG avec :

```sh
zsh scripts/test-dmg.sh dist/FanBar-0.6.3.dmg
```

## 🏗️ Architecture

FanBar sépare l’interface des écritures privilégiées :

```text
FanBar.app → XPC privilégié → FanBarHelper (root) → AppleSMC
```

Le helper n’expose aucune écriture SMC arbitraire. Il sait seulement lire les ventilateurs, appliquer une cible, un profil ou une fraction bornés, et rétablir le contrôle automatique. macOS 13 et ultérieur utilisent `SMAppService` ; macOS 11–12 passent par un enregistrement launchd compatible.

## 📦 Intégration continue et publication

Les pull requests doivent passer le lint, le formatage, une compilation sans
avertissement, les tests et la couverture du diff ; voir [docs/code-quality.md](docs/code-quality.md).

FanBar utilise Sparkle 2 pour les mises à jour en ligne. Le flux stable est
l’asset `appcast.xml` de la dernière version GitHub. Chaque mise à jour doit
passer la signature Developer ID, la notarisation et la vérification
indépendante de la signature EdDSA de FanBar.

Enregistrez une fois les identifiants de notarisation Apple sur le Mac de publication :

```sh
xcrun notarytool store-credentials FanBar-notary \
  --apple-id "votre identifiant Apple" \
  --team-id "64S5F787T9"
```

Après avoir validé sur `main` un `CFBundleShortVersionString` mis à jour et un
`CFBundleVersion` incrémenté, publiez en local avec :

```sh
gh auth login -h github.com
FANBAR_NOTARY_PROFILE=FanBar-notary zsh scripts/release-local.sh
```

La commande de publication locale exige une copie de `main` propre. Elle compile
la version universal2 ainsi que des DMG `arm64` et `x86_64` séparés, puis
signe, notarise, vérifie les DMG, calcule les sommes de contrôle, signe
l’appcast, crée le tag Git et téléverse la version GitHub. Les versions
existantes sont conservées par défaut ; n’utilisez `--replace-assets` que pour
une nouvelle tentative voulue.

La clé privée Sparkle est stockée dans le trousseau de session sous le compte
`FanBar`. Ne la régénérez pas après la première publication : les clients
installés doivent continuer à faire confiance à la même clé publique. Les
publications par CI exigent aussi la clé privée exportée dans le secret GitHub
Actions `SPARKLE_PRIVATE_KEY`.

GitHub Actions valide les compilations universal2 à chaque push et pull request.
La publication locale est le fonctionnement par défaut. Pour publier depuis la CI
à partir d’un tag, définissez la variable de dépôt `FANBAR_PUBLISH_FROM_CI=true`
et configurez `SPARKLE_PRIVATE_KEY` ainsi que les autres secrets de publication.
N’activez pas la publication par CI si vous utilisez la commande de publication locale.

Quand la publication par CI est activée, poussez un tag correspondant à la version de l’app :

```sh
git tag -a v0.6.3 -m "FanBar 0.6.3"
git push origin v0.6.3
```

### Mettre à jour le cask Homebrew

Après la publication d’une version stable (en local ou par CI), téléchargez son
DMG universel et calculez son empreinte, puis proposez la modification du cask dans une PR :

```sh
python3 scripts/update-homebrew-cask.py          # Dernière version stable
# Ou : python3 scripts/update-homebrew-cask.py v0.6.3
```

Le script nécessite Python 3 et la CLI `gh` authentifiée. Il refuse les
brouillons, les préversions et les versions sans DMG universel. Fusionnez
`Casks/fanbar.rb` dans `main` pour rendre la nouvelle version disponible via
`brew update`. Le workflow CI Homebrew vérifie le style du cask, la somme de
contrôle du téléchargement, l’installation et la désinstallation.

## ⭐ Historique des étoiles

<div align="center">

[![Graphique de l’historique des étoiles](https://api.star-history.com/svg?repos=helson-lin/FanBar&type=Date)](https://star-history.com/#helson-lin/FanBar&Date)

</div>

## 🙏 Remerciements et licence

Copyright © 2024–2026 Jarin He. Le code source de FanBar est distribué sous la [licence publique générale GNU v3.0](LICENSE).

Vous pouvez utiliser, modifier et redistribuer FanBar, y compris à des fins commerciales, à condition de respecter la GPL-3.0 : conservez les mentions de copyright et de licence, et publiez sous la même licence le code source de toute version modifiée que vous distribuez.

**Le nom et l’icône sont exclus.** Le nom « FanBar » et l’icône/le logo FanBar ne sont pas couverts par la licence GPL-3.0. Si vous distribuez une version modifiée, vous devez la renommer et remplacer l’icône pour éviter toute confusion avec le FanBar officiel.

La séquence de contrôle Apple Silicon s’appuie sur [`agoodkind/macos-smc-fan`](https://github.com/agoodkind/macos-smc-fan), sous licence MIT. Voir [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) pour l’ensemble des attributions tierces.

Merci aux personnes qui ont signalé des bugs et aidé à améliorer FanBar :

<table>
  <tr>
    <td align="center">
      <img src="docs/contributors/qingcang.png" width="64" height="64" alt="Avatar de 倾藏"><br>
      <sub><b>倾藏</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/yisasayisa.png" width="64" height="64" alt="Avatar de 一撒撒一撒"><br>
      <sub><b>一撒撒一撒</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/taolela.png" width="64" height="64" alt="Avatar de Taolela"><br>
      <sub><b>Taolela</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/estelle00.png" width="64" height="64" alt="Avatar de Estelle00"><br>
      <sub><b>Estelle00</b></sub>
    </td>
  </tr>
</table>

### Vérifications locales de compatibilité

Ouvrez **Réglages → Général → Compatibilité de l’appareil** pour vérifier chaque capteur de température, les relevés des ventilateurs et l’état du service de contrôle et des requêtes. L’accueil et les alertes de refroidissement mènent à la même vue.

Les vérifications restent sur ce Mac : elles ne contactent aucun serveur, n’installent pas le service et ne modifient pas la vitesse des ventilateurs. Un relevé manquant ou une tentative échouée ne prouve pas une incompatibilité. Un service prêt ou une requête acceptée ne vérifie pas la vitesse physique ; les preuves de requête ne valent que pour la session.

Le catalogue intégré compare localement le modèle et les versions de l’OS, de l’app et du helper. Il ne contient pour l’instant aucun enregistrement formellement vérifié et le dit explicitement. Les rapports peuvent être prévisualisés et enregistrés en JSON hors ligne. L’envoi facultatif à https://report.getfanbar.com exige un consentement explicite ; les rapports bruts restent privés sauf si l’utilisateur choisit de les publier après relecture. Des identifiants de retrait indépendants sont enregistrés dans le trousseau de ce Mac avant l’envoi. Le schéma fermé des rapports exclut les numéros de série, les identifiants uniques d’appareil, les utilisateurs, les chemins, les processus et l’historique des températures.

Le service open source Workers + D1, la matrice publique, l’interface de relecture, le schéma d’envoi et les règles de traitement se trouvent dans [services/compatibility](services/compatibility/README.md) et [contracts](contracts).
