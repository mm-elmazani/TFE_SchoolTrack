# SchoolTrack - React Dashboard

Ce dossier contient le nouveau tableau de bord web de SchoolTrack, construit avec **React**, **Vite**, **Tailwind CSS** et **shadcn/ui**.

## 🚀 Installation

1. Accédez au dossier :
   ```bash
   cd react_dashboard
   ```

2. Installez les dépendances :
   ```bash
   npm install
   ```

3. Configurez les variables d'environnement (voir section [Configuration](#-configuration)).

## 🛠️ Développement

Lancer le serveur de développement avec HMR (Hot Module Replacement) :
```bash
npm run dev
```

Le dashboard sera accessible sur `http://localhost:5173`.

## 🏗️ Production

Générer le build de production optimisé dans le dossier `dist/` :
```bash
npm run build
```

## 🧹 Qualité du Code

Lancer le linter pour vérifier et corriger les erreurs de style :
```bash
npm run lint
```

## 🧪 Tests

Lancer la suite de tests avec Vitest :
```bash
npm run test
```

## ⚙️ Configuration

Le projet utilise des variables d'environnement pour la communication avec l'API Backend.

1. Créez un fichier `.env` à la racine de ce dossier.
2. Définissez la variable suivante :
   ```text
   VITE_API_URL=http://localhost:8000
   ```
   *(Remplacez l'URL par celle de votre backend si nécessaire)*.

Consultez `.env.example` pour les valeurs par défaut.

## 🎨 Direction Artistique

Le projet suit la DA **"Professional Trust & Field Action"** :
- **Primaire** : Bleu Institutionnel (#005293)
- **Action** : Bleu Action (#1E88E5)
- **Typographie** : Inter (corps), Montserrat (titres), JetBrains Mono (données techniques).
