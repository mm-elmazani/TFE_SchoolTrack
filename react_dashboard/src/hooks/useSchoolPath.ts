import { useParams } from 'react-router-dom';

/**
 * Retourne une fonction qui prefixe un chemin avec le slug de l'ecole.
 * Usage : const sp = useSchoolPath(); <Link to={sp('/students')} />
 */
export function useSchoolPath() {
  const { schoolSlug } = useParams();
  return (path: string) => `/${schoolSlug}${path}`;
}
