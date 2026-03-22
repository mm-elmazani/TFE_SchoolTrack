import { test, expect } from '@playwright/test';

test.describe('Authentication Flow', () => {
  test('should login successfully with valid credentials and redirect to dashboard', async ({ page }) => {
    // Naviguer vers la page de login
    await page.goto('/login');

    // Vérifier qu'on est bien sur la page de login
    await expect(page.getByRole('heading', { name: 'Bienvenue' })).toBeVisible();

    // Remplir le formulaire
    // Note: On utilise les identifiants de seed du backend définis dans init.sql
    await page.getByPlaceholder('votre@email.com').fill('direction@schooltrack.be');
    await page.getByPlaceholder('Votre mot de passe').fill('password123');

    // Cliquer sur le bouton de connexion
    await page.getByRole('button', { name: 'Se connecter' }).click();

    // Vérifier la redirection vers le dashboard ("/")
    await expect(page).toHaveURL('/');

    // Vérifier la présence d'éléments du layout (ex: le nom de l'utilisateur ou le bouton de déconnexion)
    await expect(page.getByText('Direction User')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Déconnexion' })).toBeVisible();
  });

  test('should show error message with invalid credentials', async ({ page }) => {
    await page.goto('/login');

    await page.getByPlaceholder('votre@email.com').fill('direction@schooltrack.be');
    await page.getByPlaceholder('Votre mot de passe').fill('wrongpassword');

    await page.getByRole('button', { name: 'Se connecter' }).click();

    // Vérifier que le message d'erreur s'affiche
    await expect(page.getByText('Email ou mot de passe incorrect')).toBeVisible();
    
    // Vérifier qu'on est toujours sur la page de login
    await expect(page).toHaveURL(/.*login/);
  });
});
