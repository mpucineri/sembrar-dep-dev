<?php

declare(strict_types=1);

use App\Entity\User;
use App\Kernel;
use Symfony\Component\PasswordHasher\Hasher\PasswordHasherFactory;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasher;

require '/var/www/symfony/vendor/autoload.php';

if (getenv('APP_ENV') !== 'dev') {
    throw new RuntimeException('La inicialización solo está permitida en dev.');
}

$kernel = new Kernel('dev', true);
$kernel->boot();
$manager = $kernel->getContainer()->get('doctrine')->getManager();
$email = getenv('DEV_ADMIN_EMAIL') ?: 'admin@sembrar.local';

if ($manager->getRepository(User::class)->findOneBy(['email' => $email])) {
    echo "El usuario local ya existe; se conserva su contraseña.\n";
    $kernel->shutdown();
    exit(0);
}

$user = (new User())->setEmail($email)->setRoles(['ROLE_ADMIN']);
$hasher = new UserPasswordHasher(new PasswordHasherFactory([
    User::class => ['algorithm' => 'auto'],
]));
$user->setPassword($hasher->hashPassword($user, getenv('DEV_ADMIN_PASSWORD') ?: 'sembrar-dev'));
$manager->persist($user);
$manager->flush();
$kernel->shutdown();
echo "Usuario administrador local creado.\n";
