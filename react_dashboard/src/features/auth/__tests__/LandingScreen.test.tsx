import { describe, it, expect } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import LandingScreen from '../screens/LandingScreen';

describe('LandingScreen', () => {
  it('renders landing message', () => {
    render(<LandingScreen />);
    expect(screen.getByText(/Accedez au dashboard/)).toBeInTheDocument();
  });

  it('renders example URL', () => {
    render(<LandingScreen />);
    expect(screen.getByText(/votre-ecole/)).toBeInTheDocument();
  });
});
